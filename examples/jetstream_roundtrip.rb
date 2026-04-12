#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "nats-async"

url = ENV.fetch("NATS_URL", "nats://127.0.0.1:4222")
stream_name = ENV.fetch("JS_STREAM", "test_stream")
subject = ENV.fetch("JS_SUBJECT", "test_stream")
consumer = ENV.fetch("JS_CONSUMER", "example_consumer")
payload = ENV.fetch("JS_PAYLOAD", "hello jetstream")
js_api_prefix = ENV.fetch("JS_API_PREFIX", "$JS.API")

Async do |task|
  client = NatsAsync::Client.new(
    url: url,
    verbose: true,
    js_api_prefix: js_api_prefix,
    ping_interval: 1,
    ping_timeout: 1
  )
  client.start(task: task)

  js = client.jetstream
  js.add_stream?(stream_name, subjects: [subject])
  sub = js.pull_subscribe(subject, stream: stream_name, durable: consumer)

  pub_ack = js.publish(subject, payload)
  puts "published seq=#{pub_ack.seq} stream=#{pub_ack.stream}"

  message = sub.fetch(batch: 1, timeout: 2).first

  puts "received subject=#{message.subject} data=#{message.data.inspect}"
  puts "metadata=#{message.metadata.inspect}"
  message.ack

  sub.unsubscribe
  js.delete_consumer(stream_name, consumer)
  js.delete_stream(stream_name)
ensure
  sub&.unsubscribe
  client&.close
end
