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
  @fsm_notify_channel = @pg.exec(
    "SELECT 'fsm_' || c.relname FROM pg_catalog.pg_class c WHERE c.oid = 'public.orders'::regclass"
  ).getvalue(0, 0)
end

Given('I listen on the fsm notify channel for public.orders') do
  channel = @fsm_notify_channel || @pg.exec(
    "SELECT 'fsm_' || c.relname FROM pg_catalog.pg_class c WHERE c.oid = 'public.orders'::regclass"
  ).getvalue(0, 0)
  @pg.exec("LISTEN #{@pg.quote_ident(channel)}")
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

Then('I should receive a notify on channel {string}') do |expected_channel|
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
  channel = nil
  payload = nil

  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    @pg.consume_input
    msg = @pg.notifies
    if msg
      channel, payload =
        case msg
        when Array
          [msg[0], msg[2]]
        when Hash
          ch = msg[:relname] || msg['relname'] || msg[:channel] || msg['channel']
          pl = msg[:extra] || msg['extra'] || msg[:payload] || msg['payload']
          [ch, pl]
        else
          ch = msg.respond_to?(:relname) ? msg.relname : msg.channel
          pl = msg.respond_to?(:extra) ? msg.extra : msg.payload
          [ch, pl]
        end
      break
    end
    sleep 0.02
  end

  expect(channel).not_to be_nil
  expect(payload).not_to be_nil
  @last_notify_channel = channel
  @last_notify_payload = payload
  expect(channel).to eq(expected_channel)
  @last_notify_json = JSON.parse(payload)
end

Then('the notify payload should have:') do |table|
  expect(@last_notify_json).not_to be_nil
  table.raw.each do |key, value|
    key = key.strip
    value = value.strip
    case key
    when /^pk\.(.+)$/
      pk_key = Regexp.last_match(1)
      expect(@last_notify_json['pk'][pk_key].to_s).to eq(value)
    else
      expect(@last_notify_json[key].to_s).to eq(value)
    end
  end
end
