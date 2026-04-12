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
answer = client.request("math.double", "21", timeout: 1)
puts answer
```

`client.request` returns raw response data by default. Use `parse_json: true` only when
the response is expected to be JSON:

```ruby
result = client.request("service.info", "", timeout: 1, parse_json: true)
```

Use `request_message` when headers, subject, or reply metadata are needed:

```ruby
message = client.request_message("service.info", "", timeout: 1)
puts message.headers["x-request-id"]
```
