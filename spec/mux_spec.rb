# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "response multiplexing" do
  it "handles a single request successfully", :nats_server do
    Async do |task|
      client = NatsAsync::Client.new(url: nats_url, verbose: false)
      client.start(task: task)

      # Set up echo handler FIRST
      client.subscribe("echo") do |msg|
        client.publish(msg.reply, msg.data)
      end

      # Make a single request
      response = client.request("echo", "test_message", timeout: 1).wait
      expect(response.data).to eq("test_message")
    ensure
      client.close
    end
  end

  it "handles sequential requests successfully", :nats_server do
    Async do |task|
      client = NatsAsync::Client.new(url: nats_url, verbose: false)
      client.start(task: task)

      # Set up echo handler
      client.subscribe("echo") do |msg|
        client.publish(msg.reply, msg.data)
      end

      # Make 10 sequential requests
      responses = []
      10.times do |i|
        response = client.request("echo", "message_#{i}", timeout: 1).wait
        responses << response.data
      end

      expect(responses).to eq((0...10).map { |i| "message_#{i}" })
    ensure
      client.close
    end
  end

  it "handles concurrent requests efficiently", :nats_server do
    Async do |task|
      client = NatsAsync::Client.new(url: nats_url, verbose: false)
      client.start(task: task)

      # Set up echo handler
      client.subscribe("echo") do |msg|
        client.publish(msg.reply, msg.data)
      end

      # Make 20 concurrent requests - create all promises first
      promises = []
      20.times do |i|
        promises << client.request("echo", "concurrent_#{i}", timeout: 2)
      end

      # Then wait for all responses
      results = promises.map(&:wait).map(&:data)

      expect(results.sort).to eq((0...20).map { |i| "concurrent_#{i}" }.sort)
    ensure
      client.close
    end
  end

  it "times out correctly for mux requests", :nats_server do
    Async do |task|
      client = NatsAsync::Client.new(url: nats_url, verbose: false)
      client.start(task: task)

      # Request to nonexistent subject should timeout
      promise = client.request("nonexistent", "data", timeout: 0.1)
      expect {
        promise.wait
      }.to raise_error(Timeout::Error, /timeout/)

      # Other requests should still work after timeout
      client.subscribe("echo") do |msg|
        client.publish(msg.reply, msg.data)
      end
      response = client.request("echo", "after_timeout", timeout: 1).wait
      expect(response.data).to eq("after_timeout")
    ensure
      client.close
    end
  end

  it "supports callbacks via old-style requests", :nats_server do
    Async do |task|
      client = NatsAsync::Client.new(url: nats_url, verbose: false)
      client.start(task: task)

      # Set up echo handler
      client.subscribe("echo") do |msg|
        client.publish(msg.reply, msg.data)
      end

      callback_results = []
      condition = Async::Condition.new

      client.request("echo", "callback_test") do |msg|
        callback_results << msg.data
        condition.signal
      end

      condition.wait
      expect(callback_results).to eq(["callback_test"])
    ensure
      client.close
    end
  end

  it "cleans up mux subscription on close", :nats_server do
    Async do |task|
      client = NatsAsync::Client.new(url: nats_url, verbose: false)
      client.start(task: task)

      # Make a request to initialize mux
      client.subscribe("echo") do |msg|
        client.publish(msg.reply, msg.data)
      end
      client.request("echo", "test", timeout: 1).wait

      # Close should clean up mux
      client.close

      # Verify mux state is cleared
      expect(client.instance_variable_get(:@resp_mux_prefix)).to be_nil
    end
  end

  it "handles requests with headers", :nats_server do
    Async do |task|
      client = NatsAsync::Client.new(url: nats_url, verbose: false)
      client.start(task: task)

      # Set up echo handler that preserves headers
      client.subscribe("echo") do |msg|
        client.publish(msg.reply, msg.data, headers: msg.headers)
      end

      response = client.request("echo", "with_headers", headers: {"X-Custom" => "value"}, timeout: 1).wait
      expect(response.data).to eq("with_headers")
      expect(response.headers["X-Custom"]).to eq("value")
    ensure
      client.close
    end
  end
end
