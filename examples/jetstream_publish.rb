#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "nats-async"

Async do |task|
  client = NatsAsync::Client.new(url: ENV.fetch("NATS_URL", "nats://127.0.0.1:4222"))
  client.start(task: task)

  js = client.jetstream
  js.add_stream?("jobs", subjects: ["jobs.>"])

  ack = js.publish("jobs.render", "payload", headers: {"x-id" => "42"})
  puts "stored in #{ack.stream}##{ack.seq}"
ensure
  client&.close
end
