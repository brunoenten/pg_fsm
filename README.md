# pg_fsm

`pg_fsm` is a PostgreSQL extension that embeds finite state machines (FSMs) in your tables.
It stores transitions in schema metadata, enforces event/state consistency through triggers,
and lets you attach callbacks to transitions.

## Table of Contents

- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Install](#install)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [Public API Reference](#public-api-reference)
- [Validation Rules and Constraints](#validation-rules-and-constraints)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## How It Works

For each business table you want to control with a state machine:

1. `fsm.add_to_table(<table>)` adds FSM columns and triggers.
2. `fsm.add_transition(...)` defines allowed transitions in `fsm.machines`.
3. You append events by updating `new_event`.
4. A trigger computes the new state via `fsm.run_machine(...)`.
5. Optional transition callbacks execute after successful updates.

FSM logic is enforced in the database, so invalid transitions fail regardless of the
application path used to update rows.

## Requirements

- PostgreSQL 9.6+
- PostgreSQL server development tooling (`pg_config` available in `PATH`)
- Build toolchain to compile/install PostgreSQL extensions (`make`)

## Install

### 1) Build and install extension files

```bash
git clone https://github.com/brunoenten/pg_fsm.git
cd pg_fsm
make
sudo make install
```

### 2) Enable extension in your database

```sql
CREATE EXTENSION fsm;
```

The extension is installed in schema `fsm` and is not relocatable.

## Quick Start

This example wires an FSM to an `orders` table.

```sql
-- Example business table
CREATE TABLE public.orders (
  id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  customer_id bigint NOT NULL,
  total numeric(12,2) NOT NULL
);

-- Attach FSM columns/triggers
SELECT fsm.add_to_table('public.orders'::regclass);

-- Define transitions from start -> pending -> paid|cancelled
SELECT fsm.add_transition('public.orders'::regclass, 'start',   'create',  'pending');
SELECT fsm.add_transition('public.orders'::regclass, 'pending', 'pay',     'paid');
SELECT fsm.add_transition('public.orders'::regclass, 'pending', 'cancel',  'cancelled');

-- Insert row (FSM columns must remain default on INSERT)
INSERT INTO public.orders (customer_id, total) VALUES (10, 99.99);

-- Append one event to move start -> pending
UPDATE public.orders SET new_event = 'create' WHERE id = 1;

-- Append another event to move pending -> paid
UPDATE public.orders SET new_event = 'pay' WHERE id = 1;

SELECT id, fsm_previous_state, fsm_current_state
FROM public.orders
WHERE id = 1;
```

Expected states:

- after insert: `fsm_current_state = 'start'`
- after `create`: `fsm_current_state = 'pending'`
- after `pay`: `fsm_current_state = 'paid'`

## Core Concepts

### `fsm.event` type

Composite type used in event arrays:

- `name text`
- `occured_at timestamp without time zone`

### `fsm.machines` table

Stores transitions per target table:

- `table regclass`
- `state_from text`
- `event text`
- `state_to text`
- `callbacks regproc[]`

Unique constraint: `(table, state_from, event, state_to)`.

### Columns added to your table

`fsm.add_to_table(...)` adds:

- `fsm_events fsm.event[] NOT NULL DEFAULT ARRAY[]::fsm.event[]`
- `fsm_current_state text NOT NULL DEFAULT 'start'`
- `fsm_previous_state text NOT NULL DEFAULT 'start'`
- `new_event text` (the only accepted event input; trigger appends it to `fsm_events` and resets it to `NULL`)

### Triggers added to your table

- **before trigger** (`..._fsm_events_validation`) calls `fsm.events_trigger()`
  - validates update shape
  - computes next state
- **after trigger** (`..._fsm_events_callbacks`) calls `fsm.events_callbacks()`
  - executes transition callbacks

### `LISTEN` / `NOTIFY` on new events

After each update that appends exactly one event and recomputes state, the `BEFORE` trigger calls `pg_notify` on channel `fsm_<table_name>`, where `<table_name>` is the **unqualified** relation name (`TG_TABLE_NAME`, for example `orders` for `public.orders`).

The payload is a JSON object (text) with:

- `pk`: primary key column names mapped to values (empty object `{}` if the table has no primary key).
- `old_state`: FSM state before this event (`OLD.fsm_current_state`).
- `event`: name of the appended event.
- `new_state`: FSM state after running the machine (`NEW.fsm_current_state`).

Example:

```sql
LISTEN fsm_orders;
-- in another session, after a successful transition on public.orders:
-- NOTIFY payload similar to: {"pk":{"id":1},"old_state":"start","event":"create","new_state":"pending"}
```

## Public API Reference

### Table lifecycle

- `fsm.add_to_table(_table regclass) RETURNS void`
  - Adds FSM columns and triggers to a table.
- `fsm.remove_from_table(_table regclass) RETURNS void`
  - Removes FSM columns/triggers and deletes that table's transitions.

### Transition management

- `fsm.add_transition(_table regclass, _state_from text, _event text, _state_to text) RETURNS void`
- `fsm.remove_transition(_table regclass, _state_from text, _event text, _state_to text) RETURNS void`
- `fsm.execute_transition(_table regclass, initial_state text, _event text) RETURNS text`
  - Looks up the next state for one transition.

### Callback management

- `fsm.add_callback(_table regclass, _state_from text, _event text, _state_to text, callback_function regproc) RETURNS boolean`
- `fsm.remove_callback(_table regclass, _state_from text, _event text, _state_to text, callback_function regproc) RETURNS boolean`

Callbacks are executed as `SELECT callback(NEW)` in the table `AFTER UPDATE` trigger.
Callback functions should therefore accept a single argument of the target row type.

### Event append method

- `UPDATE your_table SET new_event = 'event_name' WHERE ...`
  - This is the only supported way to append events.
- `fsm.append_event(...)`
  - Deprecated and raises an error.

### State calculation utility

- `fsm.run_machine(_table regclass, _events fsm.event[]) RETURNS text`
  - Replays all events from `start`, returns resulting state.
  - Raises on invalid transitions.

### Helpers

- `fsm.row_primary_key_jsonb(_table regclass, _row record) RETURNS jsonb`
  - Used by the FSM trigger to build the `pk` object in `NOTIFY` payloads.

## Validation Rules and Constraints

The extension enforces the following:

- On `INSERT`:
  - `fsm_events` must be empty.
  - `fsm_current_state` and `fsm_previous_state` must be `'start'`.
  - `new_event` must be `NULL`.
- On `UPDATE`:
  - Direct updates to `fsm_events` are rejected.
  - At most one event can be appended per update.
  - `new_event` and direct `fsm_events` edit cannot be set in the same update.
  - `fsm_current_state`/`fsm_previous_state` are read-only.
- Transition metadata:
  - Duplicate transitions are rejected.
  - Callback list for a transition must not contain duplicates.
  - A transition delete may be rejected if it would orphan another transition's origin state.

## Troubleshooting

### `pg_fsm: Cannot insert row with non-empty event array`

You attempted to insert custom FSM values. Insert business columns only, then append events via update.

### `pg_fsm: Only one event can be appended for each update`

Split batch event appends into multiple updates.

### `Invalid event ... for state ...`

No transition exists for `(current_state, event)` in `fsm.machines` for the table.
Add or correct the transition definition.

### Callback function errors

Ensure callback signatures match the target row type (single argument: `NEW` row).

## Development

This repository includes source SQL under `src/` and a generated extension SQL file.

- extension script used by PostgreSQL: `fsm--0.1.sql`
- source fragments: `src/schemas/fsm/**`
- build system: `Makefile` (PGXS)

### Build

```bash
make
```

### Install locally

```bash
sudo make install
```

### Regenerate extension SQL (maintainers)

This project uses `pg_builder` tasks via `Rakefile`.

```bash
bundle install
bundle exec rake build_extension
```

This regenerates `fsm--<version>.sql` from source fragments.

## Contributing

Contributions are welcome.

1. Fork and create a feature branch.
2. Add tests or reproducible SQL examples for behavior changes.
3. Keep SQL comments and README docs in sync with API changes.
4. Open a pull request describing motivation and compatibility impact.

## License

GPL-3.0. See [`LICENSE.txt`](LICENSE.txt).
