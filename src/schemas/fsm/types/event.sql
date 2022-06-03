CREATE TYPE fsm.event AS (
	name text,
	occured_at timestamp without time zone
);
COMMENT ON TYPE fsm.event IS 'Event triggering a transition of a finite state machine. Contains the name of event, as well as a timestamp.';
