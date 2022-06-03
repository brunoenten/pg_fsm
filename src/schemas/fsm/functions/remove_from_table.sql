CREATE FUNCTION fsm.remove_from_table(_table regclass) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('DROP TRIGGER %s_events_trigger ON %s', replace(_table::text, '.', '_'), _table);
    EXECUTE format('ALTER TABLE %s DROP COLUMN fsm_events', _table);
    EXECUTE format('ALTER TABLE %s DROP COLUMN fsm_current_state', _table);
    DELETE FROM fsm.machines WHERE "table"=_table;
END;
$$;

COMMENT ON FUNCTION fsm.remove_from_table(_table regclass) IS 'Remove the finite state machine from the specified table';
