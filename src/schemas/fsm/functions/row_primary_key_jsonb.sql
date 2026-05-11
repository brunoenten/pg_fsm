CREATE FUNCTION fsm.row_primary_key_jsonb(_table regclass, _row record) RETURNS jsonb
    LANGUAGE plpgsql
    STABLE
    AS $$
DECLARE
    pk jsonb := '{}'::jsonb;
    col text;
    val jsonb;
BEGIN
    FOR col IN
        SELECT a.attname::text
        FROM pg_index i
        JOIN LATERAL unnest(i.indkey::smallint[]) WITH ORDINALITY AS u(attnum, ord) ON true
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = u.attnum
        WHERE i.indrelid = _table::oid
          AND i.indisprimary
        ORDER BY u.ord
    LOOP
        EXECUTE format('SELECT to_jsonb(($1).%I)', col) USING _row INTO val;
        pk := jsonb_set(pk, ARRAY[col], val, true);
    END LOOP;

    RETURN pk;
END;
$$;

COMMENT ON FUNCTION fsm.row_primary_key_jsonb(regclass, record) IS 'Build a jsonb object of primary-key column names to values for a row (empty object if no primary key).';
