# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength
# rubocop:disable RSpec/DescribeClass

require_relative "spec_helper"

RSpec.describe "client integration" do
  it "reconnects and replays subscriptions", :nats_server do
    Async do |task|
      client = NatsAsync::Client.new(
        url: nats_url,
        verbose: false,
        reconnect: true,
        reconnect_interval: 0.05,
        ping_interval: 0.05,
        ping_timeout: 0.05
      )
      messages = []
      condition = Async::Condition.new
      client.start(task: task)
      client.subscribe("reconnect.demo") do |message|
        messages << message.data
        condition.signal
      end

      client.publish("reconnect.demo", "before")
      condition.wait until messages.include?("before")

      stop_current_server
      wait_async_until { client.status == :reconnecting || client.status == :disconnected }

      start_server_for(nats_server)
      wait_async_until { client.connected? }

      client.publish("reconnect.demo", "after")
      condition.wait until messages.include?("after")

      expect(messages).to include("before", "after")
    ensure
      client&.close
    end
  end

  it "flushes stale buffered publishes without an explicit flush", :nats_server do
    Async do |task|
      subscriber = NatsAsync::Client.new(url: nats_url, verbose: false)
      publisher = NatsAsync::Client.new(url: nats_url, verbose: false, flush_delay: 0.01, flush_max_buffer: 100)
      messages = []
      condition = Async::Condition.new

      subscriber.start(task: task)
      publisher.start(task: task)
      subscriber.subscribe("flush.stale") do |message|
        messages << message.data
        condition.signal
      end
      subscriber.flush

      publisher.publish("flush.stale", "stale")
      task.with_timeout(1) { condition.wait until messages.include?("stale") }

      expect(messages).to include("stale")
    ensure
      publisher&.close
      subscriber&.close
    end
  end
end

# rubocop:enable RSpec/ExampleLength
# rubocop:enable RSpec/DescribeClass
