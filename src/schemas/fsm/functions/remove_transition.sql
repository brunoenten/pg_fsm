CREATE FUNCTION fsm.remove_transition(_table regclass, _state_from text, _event text, _state_to text) RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM fsm.machines WHERE "table"=_table AND state_from=_state_from AND "event"=_event AND state_to=_state_to;
$$;

COMMENT ON FUNCTION fsm.remove_transition(_table regclass, _state_from text, _event text, _state_to text) IS 'Remove a possible transition from specified table''s machine';
