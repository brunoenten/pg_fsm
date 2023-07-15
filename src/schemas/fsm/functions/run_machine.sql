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
