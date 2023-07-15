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

COMMENT ON FUNCTION fsm.add_callback(_table regclass, _state_from text, _event text, _state_to text, callback_function regproc) IS 'Remove a callback function from a transition';
