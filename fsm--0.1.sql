-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION fsm" to load this file. \quit
--
--
CREATE TYPE fsm.event AS (
	name text,
	occured_at timestamp without time zone
);
COMMENT ON TYPE fsm.event IS 'Event triggering a transition of a finite state machine. Contains the name of event, as well as a timestamp.';
CREATE TABLE fsm.machines (
    "table" regclass NOT NULL,
    state_from text NOT NULL,
    event text NOT NULL,
    state_to text NOT NULL
);

COMMENT ON TABLE fsm.machines IS 'Possible transitions for tables finite state machines';
-- depends_on: ["::schemas:fsm:types:event"]
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
        next_state = fsm.transition(_table, current_state, _event.name);
        IF next_state IS NULL THEN
            RAISE 'Invalid event % for state % for table %', _event.name, current_state, _table;
        END IF;
        current_state = next_state;
    END LOOP;
    RETURN current_state;
END;
$$;

COMMENT ON FUNCTION fsm.run_machine(_table regclass, _events fsm.event[]) IS 'Run the specified table''s machine with the given array of events. Returns the current state. Raise an exception if the machine enters an invalid state';
CREATE FUNCTION fsm.add_to_table(_table regclass) RETURNS void
    LANGUAGE plpgsql
    AS $$BEGIN
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_events fsm.event[] NOT NULL DEFAULT ARRAY[]::fsm.event[]', _table);
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_current_state text NOT NULL DEFAULT ''start''', _table);
    EXECUTE format('CREATE TRIGGER %s_events_trigger BEFORE INSERT OR UPDATE OF fsm_events, fsm_current_state ON %s
FOR EACH ROW EXECUTE FUNCTION fsm.events_trigger()', replace(_table::text, '.', '_'),_table);
END;    $$;

COMMENT ON FUNCTION fsm.add_to_table(_table regclass) IS 'Add a finite state machine to a table. This will add two columns to the designated table:
fsm_events, an append-only array of events
fsm_current_state, the current state of the machine for this row';
CREATE FUNCTION fsm.transition(_table regclass, initial_state text, _event text) RETURNS text
    LANGUAGE sql
    AS $$
  SELECT state_to FROM fsm.machines WHERE "table"=_table AND state_from=initial_state AND "event"=_event;
$$;

COMMENT ON FUNCTION fsm.transition(_table regclass, initial_state text, _event text) IS 'Return the next state for a given transition';
CREATE FUNCTION fsm.remove_from_table(_table regclass) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('DROP TRIGGER %s_events_trigger ON %s', replace(_table::text, '.', '_'), _table);
    EXECUTE format('ALTER TABLE %s DROP COLUMN fsm_events', _table);
    EXECUTE format('ALTER TABLE %s DROP COLUMN fsm_current_state', _table);
    DELETE FROM fsm.machines WHERE "table"=_table;
END;
$$;

COMMENT ON FUNCTION fsm.remove_from_table(_table regclass) IS 'Remove the finite state machine from the specified table';
CREATE FUNCTION fsm.add_transition(_table regclass, _state_from text, _event text, _state_to text) RETURNS void
    LANGUAGE sql
    AS $$
  INSERT INTO fsm.machines("table", "state_from", "event", state_to) VALUES (_table, _state_from, _event, _state_to);
$$;

COMMENT ON FUNCTION fsm.add_transition(_table regclass, _state_from text, _event text, _state_to text) IS 'Add a possible transition to the specified table''s machine';
-- depends_on: ["::schemas:fsm:types:event"]
CREATE FUNCTION fsm.append_event(existing_events fsm.event[], new_event_name text) RETURNS fsm.event[]
    LANGUAGE sql
    AS $$
        SELECT existing_events || (new_event_name, CURRENT_TIMESTAMP(0))::fsm.event;
    $$;

COMMENT ON FUNCTION fsm.append_event(existing_events fsm.event[], new_event_name text) IS 'Append an event to a table machine. Use with UPDATE ... SET fsm_events=fsm.append_event(event_name);';
CREATE FUNCTION fsm.remove_transition(_table regclass, _state_from text, _event text, _state_to text) RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM fsm.machines WHERE "table"=_table AND state_from=_state_from AND "event"=_event AND state_to=_state_to;
$$;

COMMENT ON FUNCTION fsm.remove_transition(_table regclass, _state_from text, _event text, _state_to text) IS 'Remove a possible transition from specified table''s machine';
CREATE FUNCTION fsm.events_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- fsm_events is append-only
  IF NEW.fsm_events IS DISTINCT FROM OLD.fsm_events AND trim_array(NEW.fsm_events, 1) IS DISTINCT FROM OLD.fsm_events THEN
    RAISE 'pg_fsm: Cannot update or delete events. Events are append-only';
  END IF;

  -- Only one new event at a time
  IF NEW.fsm_events IS DISTINCT FROM OLD.fsm_events AND (array_length(NEW.fsm_events, 1) - array_length(OLD.fsm_events, 1)) > 1 THEN
    RAISE 'pg_fsm: Only one event can be appended for each update';
  END IF;

  IF NEW.fsm_current_state IS DISTINCT FROM OLD.fsm_current_state THEN
    RAISE 'pg_fsm: Cannot force-update current_state. Column is read-only';
  END IF;

  NEW.fsm_current_state = fsm.run_machine(TG_RELID::regclass, NEW.fsm_events);
  RETURN NEW;
  -- TODO: Check that new event timestamp is not too far from CURRENT_TIMESTAMP, and absolutely not in the future

END
$$;

COMMENT ON FUNCTION fsm.events_trigger() IS 'Trigger on table containing a finite state machine to run the machine when an even is added, and enforce some constraints';
--
