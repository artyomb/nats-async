#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "nats-async"

Async do |task|
  client = NatsAsync::Client.new(url: ENV.fetch("NATS_URL", "nats://127.0.0.1:4222"))
  client.start(task: task)

  js = client.jetstream
  js.add_stream?("inference", subjects: ["jobs.>"])
  sub = js.pull_subscribe("jobs.>", stream: "inference", durable: "worker")
  js.publish("jobs.render", "payload")

  sub.fetch(batch: 5, timeout: 1).each do |message|
    puts message.data
    message.ack
  rescue StandardError
    message.nak
  end
ensure
  sub&.unsubscribe
  client&.close
end
