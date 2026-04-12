#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "nats-async"

headers = {"traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"}
payload = "\x00frame\xFF".b

Async do |task|
  client = NatsAsync::Client.new(url: ENV.fetch("NATS_URL", "nats://127.0.0.1:4222"))
  client.start(task: task)
  done = Async::Condition.new

  client.subscribe("tcp.frames") do |message|
    puts "#{message.headers["traceparent"]}: #{message.data.bytesize} bytes"
    done.signal
  end
  client.publish("tcp.frames", payload, headers: headers)
  done.wait
ensure
  client&.close
end
