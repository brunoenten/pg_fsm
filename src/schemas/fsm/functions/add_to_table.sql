CREATE FUNCTION fsm.add_to_table(_table regclass) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Create column for events list in target table
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_events fsm.event[] NOT NULL DEFAULT ARRAY[]::fsm.event[]', _table);

    -- Create columns for storing current and previous state in target table
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_current_state text NOT NULL DEFAULT ''start''', _table);
    EXECUTE format('ALTER TABLE %s ADD COLUMN fsm_previous_state text NOT NULL DEFAULT ''start''', _table);

    -- Add trigger to target table to validate list of events and machine state
    EXECUTE format('CREATE TRIGGER %s_fsm_events_validation BEFORE INSERT OR UPDATE OF fsm_events, fsm_current_state ON %s FOR EACH ROW EXECUTE FUNCTION fsm.events_trigger()', replace(_table::text, '.', '_'),_table);

    -- Add trigger to execute transition callbacks
    EXECUTE format('CREATE TRIGGER %s_fsm_events_callbacks AFTER UPDATE OF fsm_events, fsm_current_state ON %s FOR EACH ROW EXECUTE FUNCTION fsm.events_callbacks()', replace(_table::text, '.', '_'),_table);
END;
$$;

COMMENT ON FUNCTION fsm.add_to_table(_table regclass) IS 'Add a finite state machine to a table. This will add three columns to the designated table: fsm_events, an append-only array of events fsm_current_state, the current state of the machine for this row, and fsm_previous_state, the previous state of the machine for this row';
