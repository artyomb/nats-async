#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "nats-async"

url = ENV.fetch("NATS_URL", "nats://127.0.0.1:4222")
subject = ENV.fetch("NATS_SUBJECT", "demo.subject")
payload = ENV.fetch("NATS_PAYLOAD", "hello from nats-async")

connector = NatsAsync::SimpleConnector.new(url: url, verbose: true)

connector.run(duration: 1.5, ping_every: 1, ping_timeout: 1) do |client, task|
  sid = client.subscribe(subject) do |message|
    puts "received subject=#{message.subject} data=#{message.data.inspect}"
    client.unsubscribe(sid)
    task.stop
  end

  client.publish(subject, payload)
end
