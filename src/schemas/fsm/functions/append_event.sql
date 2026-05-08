-- depends_on: ["::schemas:fsm:tables:machines"]
CREATE OR REPLACE FUNCTION fsm.append_event(target_table regclass, target_pk jsonb, new_event_name text) RETURNS void
    LANGUAGE plpgsql
    AS
    $$
    BEGIN
        RAISE 'pg_fsm: fsm.append_event is deprecated. Use UPDATE % SET new_event=% WHERE ...', target_table, new_event_name;
    END
    $$;

COMMENT ON FUNCTION fsm.append_event(target_table regclass, target_pk jsonb, new_event_name text) IS 'Deprecated. Events must be appended with UPDATE <table> SET new_event = <event> WHERE ...';
