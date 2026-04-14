---
title: Flush Batching with Stale Timeout
description: Learn how the stale flush timeout prevents messages from being buffered indefinitely
---

# Flush Batching with Stale Timeout

## The Problem

When using time-based flushing with `flush_delay`, there is a critical edge case:

- **Normal case**: Buffer fills, then auto-flush runs.
- **Stale case**: Only a few messages are written, then no more writes arrive.

Without a stale timeout, messages could be buffered indefinitely if:
1. Only a few messages are sent
2. No more messages arrive
3. Client doesn't close

## The Solution

Added **stale flush timeout** via `flush_delay` parameter:

```ruby
# Connection initialization
client = NatsAsync::Client.new(
  url: "nats://127.0.0.1:4222",
  flush_delay: 0.01,        # 10ms max delay (default)
  flush_max_buffer: 5000    # Safety limit
)
```

A background stale-flush task wakes every `flush_delay` interval and flushes pending writes when they are old enough:

```ruby
def stale_flush_loop
  sleep(@flush_delay)

  loop do
    flush_pending if should_flush?
    sleep(@flush_delay)
  end
end
```

## Trade-offs

| Setting | Effect |
|---------|--------|
| `flush_delay: 0.01` (default) | 10ms max delay - low latency |
| `flush_delay: 0.05` | 50ms max delay - better throughput |
| `flush_delay: 0.1` | 100ms max delay - maximum batching |

## Testing

```ruby
# Test 1: Single message should flush within timeout
Async do
  client = NatsAsync::Client.new(
    url: NATS_URL,
    flush_delay: 0.1,
    flush_max_buffer: 5000
  )
  client.start(task: Async::Task.current)
  client.publish('test', 'Single message')
  sleep 0.2  # Wait for stale flush
  client.close
end
# ✓ Message received by subscriber
```

## Implementation Details

- **Stale check location**: Dedicated `stale_flush_loop` task with low overhead time checks
- **Lock acquisition**: `flush_pending` only acquires write lock when actually flushing
- **Default delay**: 10ms - balances batching opportunities with latency requirements
- **Separate task**: `stale_flush_loop` runs every `flush_delay` to ensure periodic flushes
