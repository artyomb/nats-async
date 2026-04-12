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
  nkey_public_key: nil
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

Core messaging:

- `publish(subject, payload = "", reply: nil, headers: nil)`
- `subscribe(subject, queue: nil, handler: nil, &block)`
- `unsubscribe(sid)`
- `request(subject, payload = "", timeout: 0.5, parse_json: false, headers: nil)`
- `request_message(subject, payload = "", timeout: 0.5, headers: nil)`

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

## `NatsAsync::Client::Message`

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

- `NatsAsync::Client::AckError`
- `NatsAsync::Client::MsgAlreadyAcked`
- `NatsAsync::Client::NotAckable`
- `NatsAsync::Client::RequestError`
- `NatsAsync::Client::ResponseParseError`
- `NatsAsync::Client::ProtocolError`
- `Timeout::Error`
