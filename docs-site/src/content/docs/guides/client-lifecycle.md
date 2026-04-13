---
title: Client Lifecycle
description: Start, flush, drain, and close a long-running NatsAsync client.
---

`NatsAsync::Client` is a long-running connection object. Start it inside an `Async` task
and close it from `ensure`.

```ruby
Async do |task|
  client = NatsAsync::Client.new(url: ENV.fetch("NATS_URL", "nats://127.0.0.1:4222"))
  client.start(task: task)

  # publish, subscribe, request, or use JetStream
ensure
  client&.close
end
```

## Start

`client.start(task:)` connects to the server, reads `INFO`, sends `CONNECT`, starts the
read loop, waits for an initial `PONG`, and starts the periodic ping loop.

Configure idle pings with:

```ruby
client = NatsAsync::Client.new(
  url: "nats://127.0.0.1:4222",
  ping_interval: 30,
  ping_timeout: 5
)
```

Set `ping_interval: nil` when a test needs to disable the periodic loop.

## Reconnect

Reconnect is owned by `NatsAsync::Client`. A failed socket session is discarded, a fresh
connection is created, and active subscriptions are replayed with their existing SIDs.
In-flight requests are rejected on disconnect. Publishes and new requests fail while the
client is disconnected or reconnecting; callers should retry explicitly when that is the
right application behavior.

```ruby
client = NatsAsync::Client.new(
  url: "nats://127.0.0.1:4222",
  reconnect: true,
  reconnect_interval: 1,
  max_reconnect_attempts: nil
)
```

## Flush

`client.flush(timeout:)` performs a `PING` / `PONG` round trip. Use it after publish calls
when the next step depends on the server receiving all writes.

```ruby
client.publish("demo.created", "hello")
client.flush(timeout: 2)
```

## Close

`client.close` stops background tasks and closes the socket. It is idempotent.

## Drain

`client.drain(timeout:)` stops the ping loop, flushes the connection, and then closes it.
Use it for worker examples where the process should finish after in-flight work is sent.

```ruby
ensure
  client&.drain(timeout: 5)
end
```

## Status helpers

Current helpers:

- `connected?`
- `closed?`
- `status`
- `last_error`
- `server_info`
- `sent_pings`
- `received_pongs`
- `received_pings`

`status` is one of `:closed`, `:connecting`, `:connected`, `:reconnecting`, or
`:disconnected`.
