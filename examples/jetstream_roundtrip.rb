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

connector = NatsAsync::SimpleConnector.new(
  url: url,
  verbose: true,
  js_api_prefix: js_api_prefix
)

connector.run(duration: 3, ping_every: 1, ping_timeout: 1) do |client, _task|
  client.request(
    client.js_api_subject("STREAM.CREATE", stream_name),
    {
      name: stream_name,
      subjects: [subject]
    },
    timeout: 2
  )

  client.request(
    client.js_api_subject("CONSUMER.CREATE", stream_name, consumer),
    {
      stream_name: stream_name,
      config: {
        name: consumer,
        durable_name: consumer,
        ack_policy: "explicit",
        deliver_policy: "new",
        filter_subject: subject
      }
    },
    timeout: 2
  )

  pub_ack = client.request(subject, payload, timeout: 2)
  puts "published seq=#{pub_ack[:seq]} stream=#{pub_ack[:stream]}"

  message = client.request(
    client.js_api_subject("CONSUMER.MSG.NEXT", stream_name, consumer),
    {batch: 1, expires: 1_000_000_000},
    timeout: 2,
    parse_json: false
  )

  puts "received subject=#{message.subject} data=#{message.data.inspect}"
  puts "metadata=#{message.metadata.inspect}"
  message.ack if message.reply

  client.request(client.js_api_subject("CONSUMER.DELETE", stream_name, consumer), {}, timeout: 2)
  client.request(client.js_api_subject("STREAM.DELETE", stream_name), {}, timeout: 2)
end
