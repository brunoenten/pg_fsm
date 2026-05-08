Given('an fsm-enabled orders table') do
  @pg.exec(<<~SQL)
    CREATE TABLE public.orders (
      id integer PRIMARY KEY,
      description text
    );
  SQL

  @pg.exec("SELECT fsm.add_to_table('public.orders'::regclass)")
  @pg.exec("SELECT fsm.add_transition('public.orders'::regclass, 'start', 'create', 'pending')")
  @pg.exec("SELECT fsm.add_transition('public.orders'::regclass, 'pending', 'pay', 'paid')")
end

Given('an order with id {int} exists') do |order_id|
  @pg.exec_params(
    'INSERT INTO public.orders (id, description) VALUES ($1, $2)',
    [order_id, "order-#{order_id}"]
  )
end

When('I append event {string} to order {int}') do |event_name, order_id|
  @pg.exec_params(
    'UPDATE public.orders SET new_event = $1 WHERE id = $2',
    [event_name, order_id]
  )
end

When('I try to append event {string} by updating fsm_events directly for order {int}') do |event_name, order_id|
  begin
    @pg.exec_params(
      "UPDATE public.orders SET fsm_events = fsm_events || ROW($1, CURRENT_TIMESTAMP(0))::fsm.event WHERE id = $2",
      [event_name, order_id]
    )
    @last_error = nil
  rescue PG::Error => e
    @last_error = e
  end
end

When('I call deprecated append_event for order {int} with event {string}') do |order_id, event_name|
  begin
    @pg.exec_params(
      "SELECT fsm.append_event('public.orders'::regclass, $1::jsonb, $2)",
      ["{\"id\":\"#{order_id}\"}", event_name]
    )
    @last_error = nil
  rescue PG::Error => e
    @last_error = e
  end
end

Then('order {int} current state should be {string}') do |order_id, expected_state|
  result = @pg.exec_params('SELECT fsm_current_state FROM public.orders WHERE id = $1', [order_id])
  expect(result.ntuples).to eq(1)
  expect(result.getvalue(0, 0)).to eq(expected_state)
end

Then('order {int} previous state should be {string}') do |order_id, expected_state|
  result = @pg.exec_params('SELECT fsm_previous_state FROM public.orders WHERE id = $1', [order_id])
  expect(result.ntuples).to eq(1)
  expect(result.getvalue(0, 0)).to eq(expected_state)
end

Then('the last database error should contain {string}') do |message_fragment|
  expect(@last_error).not_to be_nil
  expect(@last_error.message).to include(message_fragment)
end
