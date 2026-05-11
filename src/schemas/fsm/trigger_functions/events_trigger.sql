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
