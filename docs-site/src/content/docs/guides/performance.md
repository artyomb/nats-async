---
title: Performance
description: Optimizing nats-async for high-throughput publishing
---

# Performance

This guide covers performance optimization for `nats-async`, including benchmarking results and tuning recommendations.

## Quick Start

For maximum throughput, use these settings:

```ruby
client = NatsAsync::Client.new(
  url: 'nats://127.0.0.1:4222',
  verbose: false,        # Critical: Disable debug logging
  flush_delay: 0.05,     # 50ms max delay
  flush_max_buffer: 5000 # Safety limit
)
```

## Benchmark Results

### Test Configuration
- **Messages**: 10,000
- **Payload**: "Msg {i}" (average ~8 bytes)
- **Subject**: `benchmark.throughput`
- **Server**: NATS 2.12.4 (JetStream enabled)

### Single-Threaded Throughput

| Configuration | Time | Throughput | Notes |
|--------------|------|------------|-------|
| nats-pure.rb | 0.021s | **477,762 msg/s** | Baseline |
| nats-pure.rb (16 threads) | 0.016s | **628,296 msg/s** | Multi-threaded |
| nats-async (delay=10ms) | 0.022s | 458,232 msg/s | Low latency default |
| nats-async (delay=50ms) | 0.021s | **477,762 msg/s** | **Max throughput** |
| nats-async (delay=100ms) | 0.032s | 311,914 msg/s | Maximum batching |

With this run, `nats-async` at the 10ms default reached about 96% of the `nats-pure.rb` single-threaded baseline, while the 50ms throughput profile matched that baseline.

### Flush Delay Comparison

```
delay=1ms   : 0.024s -> 418,361 msg/s   (low latency)
delay=10ms  : 0.022s -> 458,232 msg/s   (default)
delay=50ms  : 0.021s -> 477,762 msg/s   (optimal)
delay=100ms : 0.032s -> 311,914 msg/s   (diminishing returns)
```

## Understanding the New API

### Time-Based vs. Count-Based Flushing

The new `flush_delay` API is more intuitive than the old `flush_batch_size`:

**Old API (count-based):**
```ruby
# How many messages before flush?
flush_batch_size: 5000
```

**New API (time-based):**
```ruby
# Max time to buffer before flush
flush_delay: 0.05  # 50ms
flush_max_buffer: 5000  # Safety limit
```

Benefits:
- **Intuitive**: Specify latency requirements, not message counts
- **Safe**: `flush_max_buffer` prevents memory explosion
- **Predictable**: Max latency is guaranteed

## Configuration Options

| Option | Default | Recommended | Description |
|--------|---------|-------------|-------------|
| `verbose` | `true` | `false` | Disable debug logging |
| `flush_delay` | `0.01` | `0.01` (default) | Max buffer time (10ms recommended) |
| `flush_max_buffer` | `5000` | `5000` | Safety limit (prevents OOM) |
| `ping_interval` | `30` | Keep default | Connection health check |
| `ping_timeout` | `5` | Keep default | Ping timeout |

## Trade-offs

### Flush Delay vs. Latency

Lower `flush_delay` reduces latency but may reduce throughput due to more frequent flushes:

| flush_delay | Throughput | Max Latency | Memory | Best For |
|-------------|------------|-------------|--------|----------|
| 1ms | ~420k msg/s | ~1ms | Minimal | Real-time apps |
| **10ms** | **~460k msg/s** | **~10ms** | ~8KB | **Default (recommended)** |
| 50ms | ~480k msg/s | ~50ms | ~40KB | High throughput |
| 100ms | ~310k msg/s | ~100ms | ~80KB | Bulk publishing |

### When to Use Different Delays

**delay = 1-5ms**: Ultra-low latency, real-time applications
**delay = 10ms (default)**: Low latency with good throughput
**delay = 50ms**: Maximum throughput, latency less critical
**delay = 100ms+**: Bulk publishing, maximum batching

## Understanding the Bottlenecks

### 1. Debug Logging (39x slowdown)

**Problem**: Every publish logs to Console:
```ruby
@logger.debug("C->S #{command}")  # ~39x slower
```

**Solution**: Set `verbose: false`
```ruby
client = NatsAsync::Client.new(verbose: false)
```

### 2. Per-Message Flush (10x slowdown)

**Problem**: Flushing after every message:
```ruby
stream.write(CR_LF, flush: true)  # Flush every message
```

**Solution**: Batch flushes with stale timeout
```ruby
# Buffered writes, auto-flush on delay or max buffer
@pending_flush_count += 1
stream.write(payload, flush: false)
```

## Usage Examples

### Maximum Throughput

For bulk publishing where latency isn't critical:

```ruby
client = NatsAsync::Client.new(
  url: 'nats://127.0.0.1:4222',
  verbose: false,
  flush_delay: 0.05,     # 50ms max delay
  flush_max_buffer: 5000
)
client.start(task: Async::Task.current)

# High-volume publishing
1_000_000.times do |i|
  client.publish('bulk.topic', "Message #{i}")
end

client.close
```

### Low Latency (Default)

For real-time applications:

```ruby
client = NatsAsync::Client.new(
  url: 'nats://127.0.0.1:4222',
  verbose: false,
  flush_delay: 0.01,     # 10ms max delay (default)
  flush_max_buffer: 5000
)
```

### Production (Balanced)

Good balance for most use cases:

```ruby
client = NatsAsync::Client.new(
  url: 'nats://127.0.0.1:4222',
  verbose: false,       # Critical for performance
  flush_delay: 0.01,    # 10ms (default)
  flush_max_buffer: 5000
)
```

## Recommendations

1. **Always disable logging in production**: `verbose: false`
2. **Use the default 10ms delay**: Good balance of throughput and latency
3. **Use 50ms delay for bulk publishing**: Maximize throughput when latency doesn't matter
4. **Always set `flush_max_buffer`**: Prevents memory explosion
5. **Monitor memory**: Higher buffer sizes use more memory

## Troubleshooting

### Low Throughput

1. Check `verbose` is set to `false`
2. Increase `flush_delay` to 50ms for better batching
3. Verify NATS server is healthy
4. Check network latency

### High Latency

1. Decrease `flush_delay` (e.g., to 1-5ms)
2. Check for blocking operations in async tasks
3. Verify no other async tasks competing for resources

### Memory Issues

1. Decrease `flush_max_buffer`
2. Check for memory leaks in subscription handlers
3. Monitor async task count

## Architecture Comparison

### nats-async vs. nats-pure.rb

| Feature | nats-async | nats-pure.rb |
|---------|------------|--------------|
| **Threading** | Async (cooperative) | Ruby threads |
| **Flush mechanism** | Time-based (default) | Background thread |
| **Default throughput** | ~460k msg/s | ~480k msg/s |
| **Tuned throughput** | ~480k msg/s @ 50ms | ~480k msg/s |
| **Multi-connection efficiency** | Excellent | Good |
| **Memory per connection** | ~8KB @ 10ms default | ~2MB |
| **Blocking behavior** | Non-blocking | Blocking per thread |

### Why nats-async is Competitive

1. **Cooperative scheduling**: No thread context switching overhead
2. **Optimized batching**: Time-based flushes with stale timeout
3. **Lower memory overhead**: Async tasks vs. native threads
4. **Better for concurrency**: Thousands of connections vs. limited threads
5. **Predictable latency**: Max delay guaranteed by `flush_delay`
