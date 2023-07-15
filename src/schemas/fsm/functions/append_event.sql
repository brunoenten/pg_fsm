-- depends_on: ["::schemas:fsm:types:event"]
CREATE OR REPLACE FUNCTION fsm.append_event(target_table regclass, target_pk jsonb, new_event_name text) RETURNS void
    LANGUAGE plpgsql
    AS
    $$
    DECLARE
        pk_column record;
        pk_conds text[];
    BEGIN
        -- Fetch target table primary key
        FOR pk_column IN SELECT a.attname, format_type(a.atttypid, a.atttypmod) AS data_type
        FROM   pg_index i
        JOIN   pg_attribute a ON a.attrelid = i.indrelid
                            AND a.attnum = ANY(i.indkey)
        WHERE  i.indrelid = target_table
        AND    i.indisprimary LOOP
            pk_conds = pk_conds || format('%I=CAST(%L AS %I)', pk_column.attname, target_pk->>pk_column.attname,pk_column.data_type);
        END LOOP;

        -- Update target row fsm_events
        EXECUTE format('UPDATE %s SET fsm_events=fsm_events || (%L, CURRENT_TIMESTAMP(0))::fsm.event WHERE %s', target_table, new_event_name, array_to_string(pk_conds,' AND '));
    END
    $$;

COMMENT ON FUNCTION fsm.append_event(existing_events fsm.event[], new_event_name text) IS 'Append an event to a table machine. Use with UPDATE ... SET fsm_events=fsm.append_event(event_name);';
