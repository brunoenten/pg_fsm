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
