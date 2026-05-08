Feature: FSM event append integration
  Scenario: Appending events through new_event changes state
    Given the schema fsm loaded
    And an fsm-enabled orders table
    And an order with id 1 exists
    When I append event "create" to order 1
    Then order 1 current state should be "pending"
    And order 1 previous state should be "start"
    When I append event "pay" to order 1
    Then order 1 current state should be "paid"
    And order 1 previous state should be "pending"

  Scenario: Direct updates to fsm_events are rejected
    Given the schema fsm loaded
    And an fsm-enabled orders table
    And an order with id 1 exists
    When I try to append event "create" by updating fsm_events directly for order 1
    Then the last database error should contain "Cannot directly update fsm_events"

  Scenario: append_event helper is rejected
    Given the schema fsm loaded
    And an fsm-enabled orders table
    And an order with id 1 exists
    When I call deprecated append_event for order 1 with event "create"
    Then the last database error should contain "fsm.append_event is deprecated"
