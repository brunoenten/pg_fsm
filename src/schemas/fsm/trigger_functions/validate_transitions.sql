CREATE FUNCTION fsm.validate_transitions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        -- Check if state_from already exists as a state_to
        IF NEW.state_from != 'start' AND NOT EXISTS (SELECT 1 FROM fsm.machines WHERE machines.state_to=NEW.state_from LIMIT 1) THEN
            RAISE 'pg_fsm: initial state must already exist as a transition result state';
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

COMMENT ON FUNCTION fsm.events_trigger() IS 'Trigger on table containing a finite state machine to run the machine when an even is added, and enforce some constraints';
