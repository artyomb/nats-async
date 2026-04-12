---
title: Getting Started
description: Install nats-async and run a minimal client.
---

`nats-async` is a Ruby gem for using NATS from `Async` tasks. It focuses on a small
client API for core NATS messaging and JetStream workflows.

## Install the gem

```bash
gem install nats-async
```

Or add it to your bundle:

```ruby
gem "nats-async"
```

## Start a client

```ruby
require "nats-async"

Async do |task|
  client = NatsAsync::Client.new(url: "nats://127.0.0.1:4222")
  client.start(task: task)

  client.subscribe("demo.subject") do |message|
    puts "received: #{message.data}"
  end

  client.publish("demo.subject", "hello")
  client.flush
ensure
  client&.close
end
```

The client is long-running. `start(task:)` opens the TCP connection, starts the read loop,
performs the first ping round trip, and starts the periodic idle ping loop.

## Run local examples

The repository includes a bundled `bin/nats-server` used by the integration specs. With
your own local NATS server, run:

```bash
bundle exec ruby examples/core_lifecycle.rb
bundle exec ruby examples/request_reply.rb
bundle exec ruby examples/jetstream_roundtrip.rb
```

Set `NATS_URL` when the server is not on `nats://127.0.0.1:4222`.

## Development commands

```bash
bundle install
bundle exec rspec
```

Build the documentation site:

```bash
cd docs-site
npm install
npm run build
```

## Read next

- [Examples](./guides/examples/)
- [Client Lifecycle](./guides/client-lifecycle/)
- [Core Messaging](./guides/core-messaging/)
- [JetStream](./guides/jetstream/)
