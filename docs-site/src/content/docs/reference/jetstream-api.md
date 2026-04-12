---
title: JetStream API
description: Reference for NatsAsync::JetStream helpers.
---

## `NatsAsync::JetStream`

Access the API from a started client:

```ruby
js = client.jetstream
```

Availability:

- `available?`
- `account_info`

Streams:

- `stream_info(name)`
- `stream_exists?(name)`
- `add_stream(name, config = nil, **options)`
- `add_stream?(name, config = nil, **options)`
- `delete_stream(name)`

Consumers:

- `consumer_info(stream, consumer)`
- `consumer_exists?(stream, consumer)`
- `add_consumer(stream, config = nil, **options)`
- `add_consumer?(stream, config = nil, **options)`
- `delete_consumer(stream, consumer)`

Publishing:

- `publish(subject, payload = "", headers: nil, timeout: 2)`

Pull consumers:

- `pull_subscribe(subject, stream:, durable: nil, consumer: nil, config: {}, create: true)`

## `PublishAck`

Returned from `js.publish`.

Fields:

- `stream`
- `seq`
- `duplicate`
- `duplicate?`

## `PullSubscription`

Returned from `js.pull_subscribe`.

Methods:

- `fetch(batch: 1, timeout: 1)`
- `unsubscribe`

`fetch` returns messages already received before timeout. Empty fetches return `[]`.

## Errors

- `NatsAsync::JetStream::Error`
- `NatsAsync::JetStream::NotFound`
- `NatsAsync::JetStream::ConsumerError`

`JetStream::Error` exposes:

- `code`
- `err_code`
- `description`
