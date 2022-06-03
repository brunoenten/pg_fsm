CREATE TABLE fsm.machines (
    "table" regclass NOT NULL,
    state_from text NOT NULL,
    event text NOT NULL,
    state_to text NOT NULL
);

COMMENT ON TABLE fsm.machines IS 'Possible transitions for tables finite state machines';
