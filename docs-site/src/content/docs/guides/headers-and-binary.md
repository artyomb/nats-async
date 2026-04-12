---
title: Headers And Binary
description: Send NATS headers and preserve payload bytes.
---

Headers are sent with `HPUB`. Header messages received from the server are parsed from
`HMSG`.

```ruby
headers = {"traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"}
payload = "\x00frame\xFF".b

client.subscribe("tcp.frames") do |message|
  puts message.headers["traceparent"]
  puts message.data.bytesize
end

client.publish("tcp.frames", payload, headers: headers)
```

## Header reads

Header keys preserve their received casing, and reads are case-insensitive:

```ruby
message.headers["traceparent"]
message.headers["TraceParent"]
```

Repeated headers are stored as arrays.

## Binary payloads

Payload size is computed with `bytesize`, and the payload is written separately from the
protocol line. This keeps NUL bytes and non-UTF-8 bytes intact.

```ruby
payload = "\x00\x01\xFF".b
client.publish("frames.raw", payload)
```

Headers and binary payloads can be used together.
