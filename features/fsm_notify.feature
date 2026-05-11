Feature: FSM NOTIFY on new events
  Scenario: pg_notify sends JSON payload when an event is appended
    Given the schema fsm loaded
    And an fsm-enabled orders table
    And an order with id 1 exists
    And I listen on the fsm notify channel for public.orders
    When I append event "create" to order 1
    Then I should receive a notify on channel "fsm_orders"
    And the notify payload should have:
      | old_state | start   |
      | event     | create  |
      | new_state | pending |
      | pk.id     | 1       |
