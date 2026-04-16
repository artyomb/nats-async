---
title: Core Messaging
description: Publish, subscribe, queue groups, and request/reply.
---

Core messaging uses NATS subjects directly. The client does not add JSON behavior unless
you ask for it.

## Publish and subscribe

```ruby
done = Async::Condition.new

client.subscribe("demo.>") do |message|
  puts "#{message.subject}: #{message.data}"
  done.signal
end

client.publish("demo.created", "hello")
done.wait
```

`message.data` is the raw payload string read from the wire.

## Queue groups

```ruby
client.subscribe("jobs.render", queue: "renderers") do |message|
  puts "worker got #{message.data}"
end

client.publish("jobs.render", "job-1")
```

NATS delivers each message to one subscriber in the queue group.

## Request/reply

Service side:

```ruby
client.subscribe("math.double") do |message|
  client.publish(message.reply, message.data.to_i * 2)
end
```

Caller side:

```ruby
promise = client.request("math.double", "21", timeout: 1)
puts promise.wait.data
```

`client.request` always returns a `RequestPromise` immediately. The request is fulfilled
from the existing client read loop when a reply arrives. The promise resolves to the full
reply `Message`. Use `wait.data` when the current task only needs the response payload.

Block form is also asynchronous. The block runs when the response arrives:

```ruby
callback = client.request("math.double", "21", timeout: 1) do |message|
  puts message.data
end

callback.wait(timeout: 1)
```

Request callbacks run on one shared client callback task, not on a per-request task. Use
the returned promise when the calling task needs to join that callback.

Parse JSON from the response payload when the response is expected to be JSON:

```ruby
message = client.request("service.info", "", timeout: 1).wait
result = JSON.parse(message.data, symbolize_names: true)
```

The same response object exposes headers, subject, and reply metadata:

```ruby
message = client.request("service.info", "", timeout: 1).wait
puts message.headers["x-request-id"]
```

Header-capable protocol replies also expose status information separately from the
header hash:

```ruby
message = client.request(subject, payload, timeout: 1).wait
puts message.status
puts message.description
```
