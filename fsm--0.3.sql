-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION fsm" to load this file. \quit
--
-- CREATE SCHEMA IF NOT EXISTS fsm;
CREATE TYPE fsm.event AS (
	name text,
	occured_at timestamp without time zone
);
COMMENT ON TYPE fsm.event IS 'Event triggering a transition of a finite state machine. Contains the name of event, as well as a timestamp.';
CREATE FUNCTION fsm.row_primary_key_jsonb(_table regclass, _row record) RETURNS jsonb
    LANGUAGE plpgsql
    STABLE
    AS $$
DECLARE
    pk jsonb := '{}'::jsonb;
    col text;
    val jsonb;
BEGIN
    FOR col IN
        SELECT a.attname::text
        FROM pg_index i
        JOIN LATERAL unnest(i.indkey::smallint[]) WITH ORDINALITY AS u(attnum, ord) ON true
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = u.attnum
        WHERE i.indrelid = _table::oid
          AND i.indisprimary
        ORDER BY u.ord
    LOOP
        EXECUTE format('SELECT to_jsonb(($1).%I)', col) USING _row INTO val;
        pk := jsonb_set(pk, ARRAY[col], val, true);
    END LOOP;

    RETURN pk;
END;
$$;

COMMENT ON FUNCTION fsm.row_primary_key_jsonb(regclass, record) IS 'Build a jsonb object of primary-key column names to values for a row (empty object if no primary key).';
CREATE FUNCTION fsm.validate_transitions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    callback regproc;
    callback_with_args regprocedure;
    new_callbacks_lower_bound smallint;
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        -- Check if state_from already exists as a state_to
        IF NEW.state_from != 'start' AND NOT EXISTS (SELECT 1 FROM fsm.machines WHERE machines.state_to=NEW.state_from LIMIT 1) THEN
            RAISE 'pg_fsm: initial state must already exist as a transition result state';
        END IF;

        -- Callbacks
        IF NEW.callbacks IS DISTINCT FROM OLD.callbacks THEN
            -- Check if callbacks are unique for this transition
            IF EXISTS (SELECT count FROM (SELECT count(unnest),unnest FROM unnest(NEW.callbacks) GROUP BY unnest) foo WHERE count >1) THEN
                RAISE 'pg_fsm: callbacks must be unique for a given transition';
            END IF;

            -- Check if new callbacks exists with the right argument
            new_callbacks_lower_bound = COALESCE(array_length(OLD.callbacks, 1), 0) + 1;
            FOR callback IN SELECT * FROM unnest(NEW.callbacks[new_callbacks_lower_bound:]) LOOP
                callback_with_args = format('%s(%s)', callback, NEW.table);
            END LOOP;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        -- Check if state_to is used as a state_from and no other transition provides it
        IF OLD.state_to != 'start' AND EXISTS (SELECT 1 FROM fsm.machines WHERE machines.state_from=OLD.state_to LIMIT 1)
                                   AND NOT EXISTS (SELECT 1 FROM fsm.machines WHERE machines.state_to=OLD.state_to LIMIT 1) THEN
            RAISE 'pg_fsm: Cannot delete transition that provides the unique initial state to another';
        END IF;
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION fsm.validate_transitions() IS 'Validate new transitions added to a machine';
-- depends_on: ["::schemas:fsm:trigger_functions:validate_transitions"]
CREATE TABLE fsm.machines
(
    "table" regclass NOT NULL,
    state_from text COLLATE pg_catalog."default" NOT NULL,
    event text COLLATE pg_catalog."default" NOT NULL,
    state_to text COLLATE pg_catalog."default" NOT NULL,
    callbacks regproc[],
    CONSTRAINT machines_unique_transition UNIQUE ("table", state_from, event, state_to)
);

COMMENT ON TABLE fsm.machines
    IS 'Possible transitions for tables finite state machines';

COMMENT ON CONSTRAINT machines_unique_transition ON fsm.machines
    IS 'Two identical transitions cannot exist';

COMMENT ON COLUMN fsm.machines.callbacks
    IS 'List of functions called with the row as unique argument when this transition happens';

CREATE CONSTRAINT TRIGGER machines_validate_transitions
    AFTER INSERT OR DELETE OR UPDATE
    ON fsm.machines
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION fsm.validate_transitions();
-- depends_on: ["::schemas:fsm:tables:machines"]
CREATE FUNCTION fsm.remove_from_table(_table regclass) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('DROP TRIGGER %s_fsm_events_validation ON %s', replace(_table::text, '.', '_'), _table);
    EXECUTE format('DROP TRIGGER %s_fsm_events_callbacks ON %s', replace(_table::text, '.', '_'), _table);
    EXECUTE format('ALTER TABLE %s DROP COLUMN fsm_events', _table);
    EXECUTE format('ALTER TABLE %s DROP COLUMN fsm_current_state', _table);
    EXECUTE format('ALTER TABLE %s DROP COLUMN fsm_previous_state', _table);
    EXECUTE format('ALTER TABLE %s DROP COLUMN new_event', _table);
    DELETE FROM fsm.machines WHERE "table"=_table;
END;
$$;

COMMENT ON FUNCTION fsm.remove_from_table(_table regclass) IS 'Remove the finite state machine from the specified table';
-- depends_on: ["::schemas:fsm:tables:machines"]
CREATE FUNCTION fsm.add_transition(_table regclass, _state_from text, _event text, _state_to text) RETURNS void
    LANGUAGE sql
    AS $$
  INSERT INTO fsm.machines("table", "state_from", "event", state_to) VALUES (_table, _state_from, _event, _state_to);
$$;

COMMENT ON FUNCTION fsm.add_transition(_table regclass, _state_from text, _event text, _state_to text) IS 'Add a possible transition to the specified table''s machine';
-- depends_on: ["::schemas:fsm:tables:machines"]
CREATE FUNCTION fsm.remove_transition(_table regclass, _state_from text, _event text, _state_to text) RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM fsm.machines WHERE "table"=_table AND state_from=_state_from AND "event"=_event AND state_to=_state_to;
$$;

COMMENT ON FUNCTION fsm.remove_transition(_table regclass, _state_from text, _event text, _state_to text) IS 'Remove a possible transition from specified table''s machine';
-- depends_on: ["::schemas:fsm:tables:machines"]
CREATE FUNCTION fsm.remove_callback(_table regclass, _state_from text, _event text, _state_to text, callback_function regproc) RETURNS boolean
    LANGUAGE sql
    AS $$

    UPDATE fsm.machines SET callbacks = array_remove(callbacks,callback_function)
            WHERE       machines.table = _table
                AND     machines.state_from = _state_from
                AND     machines.event = _event
                AND     machines.state_to = _state_to
            RETURNING true AS found;

$$;

COMMENT ON FUNCTION fsm.remove_callback(_table regclass, _state_from text, _event text, _state_to text, callback_function regproc) IS 'Remove a callback function from a transition';
-- depends_on: ["::schemas:fsm:tables:machines"]
CREATE FUNCTION fsm.add_callback(_table regclass, _state_from text, _event text, _state_to text, callback_function regproc) RETURNS boolean
    LANGUAGE sql
    AS $$

    UPDATE fsm.machines SET callbacks = callbacks || callback_function
            WHERE       machines.table = _table
                AND     machines.state_from = _state_from
                AND     machines.event = _event
                AND     machines.state_to = _state_to
            RETURNING true AS found;

$$;

COMMENT ON FUNCTION fsm.add_callback(_table regclass, _state_from text, _event text, _state_to text, callback_function regproc) IS 'Add a callback function to a transition';
-- depends_on: ["::schemas:fsm:tables:machines"]
CREATE FUNCTION fsm.execute_transition(_table regclass, initial_state text, _event text) RETURNS text
    LANGUAGE sql
    AS $$
  SELECT state_to FROM fsm.machines WHERE "table"=_table AND state_from=initial_state AND "event"=_event;
$$;

COMMENT ON FUNCTION fsm.execute_transition(_table regclass, initial_state text, _event text) IS 'Return the next state for a given transition';
-- depends_on: ["::schemas:fsm:tables:machines"]
CREATE FUNCTION fsm.add_to_table(_table regclass) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Create column for events list in target table
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_events fsm.event[] NOT NULL DEFAULT ARRAY[]::fsm.event[]', _table);
    EXECUTE format('ALTER TABLE %s ADD COLUMN new_event text', _table);

    -- Create columns for storing current and previous state in target table
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_current_state text NOT NULL DEFAULT ''start''', _table);
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_previous_state text NOT NULL DEFAULT ''start''', _table);

    -- Add trigger to target table to validate list of events and machine state
    EXECUTE format('CREATE TRIGGER %s_fsm_events_validation BEFORE INSERT OR UPDATE OF fsm_events, fsm_current_state, new_event ON %s FOR EACH ROW EXECUTE FUNCTION fsm.events_trigger()', replace(_table::text, '.', '_'),_table);

    -- Add trigger to execute transition callbacks
    EXECUTE format('CREATE TRIGGER %s_fsm_events_callbacks AFTER UPDATE OF fsm_events, fsm_current_state, new_event ON %s FOR EACH ROW EXECUTE FUNCTION fsm.events_callbacks()', replace(_table::text, '.', '_'),_table);
END;
$$;

COMMENT ON FUNCTION fsm.add_to_table(_table regclass) IS 'Add a finite state machine to a table. This adds fsm_events (append-only event array), fsm_current_state, fsm_previous_state, and new_event (single-event input column appended to fsm_events on update).';
-- depends_on: ["::schemas:fsm:types:event", "::schemas:fsm:tables:machines"]
CREATE FUNCTION fsm.run_machine(_table regclass, _events fsm.event[]) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    _event fsm.event;
    current_state text;
    next_state text;
BEGIN
    current_state = 'start';
    FOREACH _event IN ARRAY _events LOOP
        next_state = fsm.execute_transition(_table, current_state, _event.name);
        IF next_state IS NULL THEN
            RAISE 'Invalid event % for state % for table %', _event.name, current_state, _table;
        END IF;
        current_state = next_state;
    END LOOP;
    RETURN current_state;
END;
$$;

COMMENT ON FUNCTION fsm.run_machine(_table regclass, _events fsm.event[]) IS 'Run the specified table''s machine with the given array of events. Returns the current state. Raise an exception if the machine enters an invalid state';
-- depends_on: ["::schemas:fsm:tables:machines"]
CREATE OR REPLACE FUNCTION fsm.append_event(target_table regclass, target_pk jsonb, new_event_name text) RETURNS void
    LANGUAGE plpgsql
    AS
    $$
    BEGIN
        RAISE 'pg_fsm: fsm.append_event is deprecated. Use UPDATE % SET new_event=% WHERE ...', target_table, new_event_name;
    END
    $$;

COMMENT ON FUNCTION fsm.append_event(target_table regclass, target_pk jsonb, new_event_name text) IS 'Deprecated. Events must be appended with UPDATE <table> SET new_event = <event> WHERE ...';
-- depends_on: ["::schemas:fsm:types:event"]
CREATE FUNCTION fsm.events_callbacks() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    new_event text;
    callback regproc;
BEGIN
    IF NEW.fsm_events IS DISTINCT FROM OLD.fsm_events THEN
        -- Get new event
        new_event = NEW.fsm_events[array_upper(NEW.fsm_events, 1)].name;

        -- Execute callbacks from transition
        FOR callback IN SELECT unnest(callbacks) FROM fsm.machines WHERE "table"=TG_RELID AND state_from=NEW.fsm_previous_state AND "event"=new_event AND state_to=NEW.fsm_current_state LOOP
            EXECUTE format('SELECT %s($1)', callback) USING NEW;
        END LOOP;
    END IF;

    RETURN NULL;
END
$$;

COMMENT ON FUNCTION fsm.events_callbacks() IS 'Trigger on table containing a finite state machine to run transitions callbacks';
-- depends_on: ["::schemas:fsm:functions:row_primary_key_jsonb", "::schemas:fsm:functions:run_machine"]
CREATE FUNCTION fsm.events_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    notify_payload text;
BEGIN

  IF TG_OP = 'INSERT' THEN
    -- fsm_events must be empty, and fsm_current_state / fsm_previous_state must be 'start' during INSERT
    IF array_length(NEW.fsm_events,1) IS NOT NULL THEN
      RAISE 'pg_fsm: Cannot insert row with non-empty event array';
    END IF;

    IF NEW.fsm_current_state IS DISTINCT FROM 'start'  OR NEW.fsm_previous_state IS DISTINCT FROM 'start' THEN
      RAISE 'pg_fsm: Cannot insert row with non-default states';
    END IF;
    IF NEW.new_event IS NOT NULL THEN
      RAISE 'pg_fsm: Cannot insert row with new_event set';
    END IF;
  ELSE -- UPDATE
    IF NEW.fsm_events IS DISTINCT FROM OLD.fsm_events THEN
      RAISE 'pg_fsm: Cannot directly update fsm_events. Use column new_event';
    END IF;
    -- new_event is a write-only helper; append it to fsm_events when provided.
    IF NEW.new_event IS NOT NULL THEN
      NEW.fsm_events = NEW.fsm_events || (NEW.new_event, CURRENT_TIMESTAMP(0))::fsm.event;
    END IF;

    -- fsm_events is append-only
    IF NEW.fsm_events IS DISTINCT FROM OLD.fsm_events AND trim_array(NEW.fsm_events, 1) IS DISTINCT FROM OLD.fsm_events THEN
      RAISE 'pg_fsm: Cannot update or delete events. Events are append-only';
    END IF;

    -- Only one new event at a time
    IF NEW.fsm_events IS DISTINCT FROM OLD.fsm_events AND (array_length(NEW.fsm_events, 1) - array_length(OLD.fsm_events, 1)) > 1 THEN
      RAISE 'pg_fsm: Only one event can be appended for each update';
    END IF;

    -- fsm_current_state and fsm_previous_state are read only
    IF NEW.fsm_current_state IS DISTINCT FROM OLD.fsm_current_state OR NEW.fsm_previous_state IS DISTINCT FROM OLD.fsm_previous_state THEN
      RAISE 'pg_fsm: Cannot force-update states. Columns fsm_current_state and fsm_previous_state are read-only';
    END IF;

    NEW.fsm_previous_state = NEW.fsm_current_state;
    NEW.fsm_current_state = fsm.run_machine(TG_RELID::regclass, NEW.fsm_events);
    NEW.new_event = NULL;

    IF NEW.fsm_events IS DISTINCT FROM OLD.fsm_events THEN
      notify_payload := jsonb_build_object(
        'pk', fsm.row_primary_key_jsonb(TG_RELID::regclass, NEW),
        'old_state', OLD.fsm_current_state,
        'event', NEW.fsm_events[array_upper(NEW.fsm_events, 1)].name,
        'new_state', NEW.fsm_current_state
      )::text;
      PERFORM pg_notify('fsm_' || TG_TABLE_NAME, notify_payload);
    END IF;
  END IF;
  RETURN NEW;
END
$$;

COMMENT ON FUNCTION fsm.events_trigger() IS 'Trigger on table containing a finite state machine to run the machine when an even is added, and enforce some constraints';
--
