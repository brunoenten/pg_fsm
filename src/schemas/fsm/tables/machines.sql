-- depends_on: ["::schemas:fsm:trigger_functions:validate_transitions"]
CREATE TABLE fsm.machines
(
    "table" regclass NOT NULL,
    state_from text COLLATE pg_catalog."default" NOT NULL,
    event text COLLATE pg_catalog."default" NOT NULL,
    state_to text COLLATE pg_catalog."default" NOT NULL,
    callbacks regproc[],
    CONSTRAINT machines_unique_transition UNIQUE ("table", state_from, event, state_to)
);

COMMENT ON TABLE fsm.machines
    IS 'Possible transitions for tables finite state machines';

COMMENT ON CONSTRAINT machines_unique_transition ON fsm.machines
    IS 'Two identical transitions cannot exist';

COMMENT ON COLUMN fsm.machines.callbacks
    IS 'List of functions called with the row as unique argument when this transition happens';

CREATE CONSTRAINT TRIGGER machines_validate_transitions
    AFTER INSERT OR DELETE OR UPDATE
    ON fsm.machines
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION fsm.validate_transitions();