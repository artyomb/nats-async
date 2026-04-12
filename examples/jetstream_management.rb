#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "nats-async"

Async do |task|
  client = NatsAsync::Client.new(url: ENV.fetch("NATS_URL", "nats://127.0.0.1:4222"))
  client.start(task: task)

  js = client.jetstream
  js.add_stream?("inference", subjects: ["jobs.>"])
  puts js.stream_exists?("inference")
  js.add_consumer?("inference", durable_name: "worker", ack_policy: "explicit", filter_subject: "jobs.>")
  puts js.consumer_info("inference", "worker").dig(:config, :durable_name)
ensure
  client&.close
end
