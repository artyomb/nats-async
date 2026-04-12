#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "nats-async"

Async do |task|
  client = NatsAsync::Client.new(url: ENV.fetch("NATS_URL", "nats://127.0.0.1:4222"))
  client.start(task: task)
  done = Async::Condition.new

  client.subscribe("demo.>") do |message|
    puts "#{message.subject}: #{message.data}"
    done.signal
  end
  client.publish("demo.created", "hello")
  done.wait
ensure
  client&.close
end
