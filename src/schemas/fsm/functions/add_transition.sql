CREATE FUNCTION fsm.add_transition(_table regclass, _state_from text, _event text, _state_to text) RETURNS void
    LANGUAGE sql
    AS $$
  INSERT INTO fsm.machines("table", "state_from", "event", state_to) VALUES (_table, _state_from, _event, _state_to);
$$;

COMMENT ON FUNCTION fsm.add_transition(_table regclass, _state_from text, _event text, _state_to text) IS 'Add a possible transition to the specified table''s machine';
