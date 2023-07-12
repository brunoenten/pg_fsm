CREATE FUNCTION fsm.events_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- fsm_events is append-only
  IF NEW.fsm_events IS DISTINCT FROM OLD.fsm_events AND trim_array(NEW.fsm_events, 1) IS DISTINCT FROM OLD.fsm_events THEN
    RAISE 'pg_fsm: Cannot update or delete events. Events are append-only';
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
