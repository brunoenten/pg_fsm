-- depends_on: ["::schemas:fsm:types:event"]
CREATE FUNCTION fsm.append_event(existing_events fsm.event[], new_event_name text) RETURNS fsm.event[]
    LANGUAGE sql
    AS $$
        SELECT existing_events || (new_event_name, CURRENT_TIMESTAMP(0))::fsm.event;
    $$;

COMMENT ON FUNCTION fsm.append_event(existing_events fsm.event[], new_event_name text) IS 'Append an event to a table machine. Use with UPDATE ... SET fsm_events=fsm.append_event(event_name);';
