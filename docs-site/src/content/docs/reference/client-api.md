---
title: Client API
description: Reference for NatsAsync::Client and NatsAsync::Message.
---

## `NatsAsync::Client`

Constructor:

```ruby
NatsAsync::Client.new(
  url: "nats://127.0.0.1:4222",
  verbose: true,
  js_api_prefix: "$JS.API",
  ping_interval: 30,
  ping_timeout: 5,
  tls: nil,
  tls_verify: true,
  tls_ca_file: nil,
  tls_ca_path: nil,
  tls_hostname: nil,
  tls_handshake_first: false,
  user: nil,
  password: nil,
  nkey_seed: nil,
  nkey_seed_file: nil,
  nkey_public_key: nil,
  reconnect: false,
  reconnect_interval: 1,
  max_reconnect_attempts: nil
)
```

Lifecycle:

- `start(task:)`
- `flush(timeout: 2)`
- `drain(timeout: 5)`
- `close`
- `stop`
- `connected?`
- `closed?`
- `last_error`
- `status`

Core messaging:

- `publish(subject, payload = "", reply: nil, headers: nil)`
- `subscribe(subject, queue: nil, handler: nil, &block)`
- `unsubscribe(sid)`
- `request(subject, payload = "", timeout: 0.5, headers: nil, &block)`

`request` returns `NatsAsync::Client::RequestPromise` immediately. If a block is given,
the block is called asynchronously when the response arrives. The implementation is
event-driven through the existing read loop, one shared request timeout loop, and one
shared callback task. The promise resolves to the reply `NatsAsync::Message`.

JetStream:

- `jetstream`
- `js_api_subject(*tokens)`
- `resolve_backend(mode: :auto, stream: nil)`

Operational fields:

- `server_info`
- `js_api_prefix`
- `sent_pings`
- `received_pongs`
- `received_pings`
- `status`

Connection statuses:

- `:closed`
- `:connecting`
- `:connected`
- `:reconnecting`
- `:disconnected`

## `NatsAsync::Client::RequestPromise`

Returned from `client.request`.

`wait` returns the reply `NatsAsync::Message` when fulfilled and raises the stored error when
rejected. `value` returns the fulfilled message, returns `nil` while pending, and raises the
stored error when rejected.

Methods:

- `id`
- `status`
- `pending?`
- `fulfilled?`
- `rejected?`
- `wait(timeout: nil)`
- `value`
- `error`

Statuses:

- `:pending`
- `:fulfilled`
- `:rejected`

## `NatsAsync::Message`

Fields:

- `subject`
- `sid`
- `reply`
- `data`
- `headers`
- `header`

Ack methods:

- `ack`
- `ack_sync(timeout: 0.5)`
- `nak(delay: nil, timeout: nil)`
- `term(timeout: nil)`
- `in_progress(timeout: nil)`
- `ackable?`
- `acked?`
- `metadata`

## Errors

- `NatsAsync::Error`
- `NatsAsync::ConnectionError`
- `NatsAsync::AckError`
- `NatsAsync::MsgAlreadyAcked`
- `NatsAsync::NotAckable`
- `NatsAsync::RequestError`
- `NatsAsync::ProtocolError`
- `Timeout::Error`
