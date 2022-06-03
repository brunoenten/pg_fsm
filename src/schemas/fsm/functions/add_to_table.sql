CREATE FUNCTION fsm.add_to_table(_table regclass) RETURNS void
    LANGUAGE plpgsql
    AS $$BEGIN
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_events fsm.event[] NOT NULL DEFAULT ARRAY[]::fsm.event[]', _table);
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_current_state text NOT NULL DEFAULT ''start''', _table);
    EXECUTE format('CREATE TRIGGER %s_events_trigger BEFORE INSERT OR UPDATE OF fsm_events, fsm_current_state ON %s
FOR EACH ROW EXECUTE FUNCTION fsm.events_trigger()', replace(_table::text, '.', '_'),_table);
END;    $$;

COMMENT ON FUNCTION fsm.add_to_table(_table regclass) IS 'Add a finite state machine to a table. This will add two columns to the designated table:
fsm_events, an append-only array of events
fsm_current_state, the current state of the machine for this row';
