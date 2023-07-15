-- depends_on: ["::schemas:fsm:types:event"]
CREATE OR REPLACE FUNCTION fsm.events_callbacks() RETURNS trigger
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
