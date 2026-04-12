---
title: JetStream
description: Manage streams, publish with acknowledgements, and use pull consumers.
---

Use `client.jetstream` for JetStream management and pull-consumer workflows.

```ruby
js = client.jetstream
```

## Streams

```ruby
js.add_stream?("jobs", subjects: ["jobs.>"])
puts js.stream_exists?("jobs")
info = js.stream_info("jobs")
```

`add_stream?` creates the stream only when it is missing. It returns `true` when the
stream was created and `false` when it already existed.

## Consumers

```ruby
js.add_consumer?(
  "jobs",
  durable_name: "worker",
  ack_policy: "explicit",
  filter_subject: "jobs.>"
)

consumer = js.consumer_info("jobs", "worker")
puts consumer.dig(:config, :durable_name)
```

`add_consumer?` has the same create-if-missing semantics as `add_stream?`.

## Publish acknowledgements

```ruby
ack = js.publish("jobs.render", "payload", headers: {"x-id" => "42"})
puts "stored in #{ack.stream}##{ack.seq}"
```

The returned acknowledgement exposes `stream`, `seq`, and `duplicate?`.

## Pull consumers

```ruby
sub = js.pull_subscribe("jobs.>", stream: "jobs", durable: "worker")
js.publish("jobs.render", "payload")

sub.fetch(batch: 5, timeout: 1).each do |message|
  puts message.data
  message.ack
rescue StandardError
  message.nak
end
```

Always unsubscribe local pull subscriptions when the process is done:

```ruby
ensure
  sub&.unsubscribe
end
```

## Ack lifecycle

JetStream messages carry an ack reply subject. The message API supports:

- `ack`
- `ack_sync(timeout:)`
- `nak(delay: nil)`
- `term`
- `in_progress`
- `ackable?`
- `acked?`
- `metadata`

`ack`, `ack_sync`, `nak`, and `term` are terminal. `in_progress` is non-terminal and can
be repeated while work is still running.

## Backend detection

```ruby
backend = client.resolve_backend(mode: :auto, stream: "inference")
```

Modes:

- `:core`: return `:core` without JetStream checks.
- `:jetstream`: require the stream to exist or raise.
- `:auto`: return `:jetstream` when the stream exists, otherwise `:core`.
