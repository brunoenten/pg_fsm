CREATE FUNCTION fsm.events_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

  IF TG_OP = 'INSERT' THEN
    -- fsm_events must be empty, and fsm_current_state / fsm_previous_state must be 'start' during INSERT
    IF array_length(NEW.fsm_events,1) IS NOT NULL THEN
      RAISE 'pg_fsm: Cannot insert row with non-empty event array';
    END IF;

    IF NEW.fsm_current_state IS DISTINCT FROM 'start'  OR NEW.fsm_previous_state IS DISTINCT FROM 'start' THEN
      RAISE 'pg_fsm: Cannot insert row with non-default states';
    END IF;
  ELSE -- UPDATE
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
  END IF;
  RETURN NEW;
END
$$;

COMMENT ON FUNCTION fsm.events_trigger() IS 'Trigger on table containing a finite state machine to run the machine when an even is added, and enforce some constraints';
