#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "nats-async"

Async do |task|
  client = NatsAsync::Client.new(url: ENV.fetch("NATS_URL", "nats://127.0.0.1:4222"))
  client.start(task: task)

  client.jetstream.add_stream?("inference", subjects: ["jobs.>"])
  backend = client.resolve_backend(mode: :auto, stream: "inference")
  puts "using #{backend}"
ensure
  client&.close
end
