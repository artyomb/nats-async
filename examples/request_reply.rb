#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "nats-async"

Async do |task|
  client = NatsAsync::Client.new(url: ENV.fetch("NATS_URL", "nats://127.0.0.1:4222"))
  client.start(task: task)

  client.subscribe("math.double") { |message| client.publish(message.reply, message.data.to_i * 2) }
  puts client.request("math.double", "21", timeout: 1)
ensure
  client&.close
end
