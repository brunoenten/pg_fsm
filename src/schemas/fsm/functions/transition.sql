CREATE FUNCTION fsm.transition(_table regclass, initial_state text, _event text) RETURNS text
    LANGUAGE sql
    AS $$
  SELECT state_to FROM fsm.machines WHERE "table"=_table AND state_from=initial_state AND "event"=_event;
$$;

COMMENT ON FUNCTION fsm.transition(_table regclass, initial_state text, _event text) IS 'Return the next state for a given transition';
