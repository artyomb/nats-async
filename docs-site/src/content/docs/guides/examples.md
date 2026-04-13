---
title: Examples
description: Runnable examples that define the intended nats-async API shape.
---

The examples are intentionally short. They show the API the gem is expected to support
without turning each file into a test harness.

## Core lifecycle

Source: [`examples/core_lifecycle.rb`](https://github.com/artyomb/nats-async/blob/main/examples/core_lifecycle.rb)

```bash
bundle exec ruby examples/core_lifecycle.rb
```

Shows `NatsAsync::Client`, explicit `start(task:)`, a subscription callback, one publish,
and `close` in `ensure`.

## Queue group

Source: [`examples/queue_group.rb`](https://github.com/artyomb/nats-async/blob/main/examples/queue_group.rb)

```bash
bundle exec ruby examples/queue_group.rb
```

Shows `subscribe(subject, queue:)` and `drain(timeout:)` for a worker-style subscriber.

## Request/reply

Source: [`examples/request_reply.rb`](https://github.com/artyomb/nats-async/blob/main/examples/request_reply.rb)

```bash
bundle exec ruby examples/request_reply.rb
```

Shows a service publishing to `message.reply`, async request callbacks, and a
message-oriented request promise with `wait.data`.

## Headers and binary payloads

Source: [`examples/headers_and_binary.rb`](https://github.com/artyomb/nats-async/blob/main/examples/headers_and_binary.rb)

```bash
bundle exec ruby examples/headers_and_binary.rb
```

Shows NATS headers through `HPUB` / `HMSG` and byte-preserving payload handling.

## JetStream management

Source: [`examples/jetstream_management.rb`](https://github.com/artyomb/nats-async/blob/main/examples/jetstream_management.rb)

```bash
bundle exec ruby examples/jetstream_management.rb
```

Shows `add_stream?`, `stream_exists?`, `add_consumer?`, and `consumer_info`.

## JetStream publish

Source: [`examples/jetstream_publish.rb`](https://github.com/artyomb/nats-async/blob/main/examples/jetstream_publish.rb)

```bash
bundle exec ruby examples/jetstream_publish.rb
```

Shows `js.publish` returning a publish acknowledgement with `stream` and `seq`.

## JetStream pull consumer

Source: [`examples/jetstream_pull_consumer.rb`](https://github.com/artyomb/nats-async/blob/main/examples/jetstream_pull_consumer.rb)

```bash
bundle exec ruby examples/jetstream_pull_consumer.rb
```

Shows durable pull subscription setup, `fetch(batch:, timeout:)`, and message ack/nak.

## Backend detection

Source: [`examples/backend_detection.rb`](https://github.com/artyomb/nats-async/blob/main/examples/backend_detection.rb)

```bash
bundle exec ruby examples/backend_detection.rb
```

Shows `client.resolve_backend(mode: :auto, stream:)` selecting `:jetstream` when the
stream exists and falling back to `:core` otherwise.

## Full JetStream round trip

Source: [`examples/jetstream_roundtrip.rb`](https://github.com/artyomb/nats-async/blob/main/examples/jetstream_roundtrip.rb)

```bash
bundle exec ruby examples/jetstream_roundtrip.rb
```

Shows stream creation, durable pull subscription, publish ack, fetch, message metadata,
ack, and cleanup.
