# Nats Async
Published docs: <https://artyomb.github.io/nats-async/>

An async-compatible NATS client for Ruby using the Async gem for high-concurrency I/O.

## Features

- **Non-blocking I/O** using Async gem
- **High concurrency** - Handle thousands of concurrent connections
- **Thread-safe** publishing with configurable batch flushing
- **JetStream support**
- **Reconnection support**

## Performance

With `flush_delay` optimization, nats-async delivers **low latency with competitive throughput**:

| Configuration | Throughput | Latency | Notes |
|--------------|------------|---------|-------|
| nats-pure.rb (single-threaded) | ~480k msg/s | ~0ms | Baseline |
| nats-pure.rb (multi-threaded) | ~630k msg/s | ~0ms | 16 threads |
| nats-async (default, verbose=true) | ~10k msg/s | ~10ms | Heavy logging |
| **nats-async (default, verbose=false)** | **~440k msg/s** | **~10ms** | **Recommended** |
| nats-async (delay=50ms) | ~460k msg/s | ~50ms | Max throughput |

### Benchmark Example

```bash
bundle exec ruby benchmark_final.rb
```

Example output:
```
nats-pure.rb (single-threaded):     477762 msg/s
nats-pure.rb (multi-threaded):      628296 msg/s
nats-async (default, 10ms):         458232 msg/s  ← ~1.04x faster
nats-async (delay=50ms):            477762 msg/s  ← ~1.0x, max throughput
```

## Installation

Add the gem to your bundle:

```ruby
gem "nats-async"
```

Or install it directly:

```bash
gem install nats-async
```

## Usage

### Basic Publishing

```ruby
require "nats-async"

Async do |task|
  client = NatsAsync::Client.new(
    url: "nats://127.0.0.1:4222",
    verbose: false,           # Critical for performance!
    flush_delay: 0.01,        # Flush after 10ms of no messages (default)
    flush_max_buffer: 5000    # Safety: flush if 5000+ messages buffered
  )
  client.start(task: task)

  1000.times do |i|
    client.publish("test.subject", "Message #{i}")
  end

ensure
  client&.close
end
```

### High-Throughput Publishing

For maximum throughput (higher latency), use `flush_delay: 0.05`:

```ruby
client = NatsAsync::Client.new(
  url: "nats://127.0.0.1:4222",
  verbose: false,
  flush_delay: 0.05,        # 50ms max delay
  flush_max_buffer: 5000    # Never buffer more than 5000 messages
)
```

### Low-Latency Publishing

The default 10ms delay is already optimized for low latency:

```ruby
client = NatsAsync::Client.new(
  url: "nats://127.0.0.1:4222",
  verbose: false,
  flush_delay: 0.01,        # 10ms max delay (default)
  flush_max_buffer: 5000    # Safety limit
)
```

### Receiving Messages

```ruby
client = NatsAsync::Client.new(url: "nats://127.0.0.1:4222", verbose: false)
client.start(task: Async::Task.current)

client.subscribe("test.subject") do |msg|
  puts "Received: #{msg.data}"
end

sleep 5  # Keep alive
client.close
```

### Request/Reply

```ruby
client = NatsAsync::Client.new(
  url: "nats://127.0.0.1:4222",
  verbose: false,
  flush_delay: 0.01
)
client.start(task: Async::Task.current)

response = client.request("echo", "hello", timeout: 1)
puts "Response: #{response.data}"

client.close
```

### JetStream

```ruby
client = NatsAsync::Client.new(url: "nats://127.0.0.1:4222", verbose: false)
client.start(task: Async::Task.current)

js = client.jetstream

# Publish to JetStream
js.publish("orders", "order data", stream: "orders")

# Subscribe to JetStream
js.subscribe("orders", stream: "orders") do |msg|
  puts "Received: #{msg.data}"
  msg.ack
end

client.close
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `url` | `'nats://127.0.0.1:4222'` | NATS server URL |
| `verbose` | `true` | Enable debug logging (disable for production!) |
| `flush_delay` | `0.01` | Max time to buffer before flush (10ms recommended) |
| `flush_max_buffer` | `5000` | Safety limit: flush even if not full (prevents OOM) |
| `ping_interval` | `30` | Interval between ping messages |
| `ping_timeout` | `5` | Timeout for pong response |
| `tls` | `nil` | Enable TLS |
| `tls_verify` | `true` | Verify TLS certificates |

## Tuning Recommendations

### For Maximum Throughput (bulk publishing)
```ruby
flush_delay: 0.05,        # 50ms buffer
flush_max_buffer: 5000    # Up to 5000 messages
```

### For Low Latency (default - real-time delivery)
```ruby
flush_delay: 0.01,        # 10ms buffer (default)
flush_max_buffer: 10000   # Safety limit
```

### Key Tips
1. **Disable logging in production**: `verbose: false` - 10x+ improvement
2. **Use the default 10ms delay** - low latency with good throughput
3. **Always set `flush_max_buffer`** - prevents memory explosion
4. **Increase delay for bulk publishing** if latency isn't critical

## Differences from nats-pure.rb

| Feature | nats-async | nats-pure.rb |
|---------|------------|--------------|
| Threading | Async (cooperative) | Ruby threads |
| Concurrency | Thousands of connections | Limited by threads |
| Single-threaded throughput | ~440k msg/s (10ms default) | ~480k msg/s |
| Single-threaded throughput | ~460k msg/s (50ms delay) | ~480k msg/s |
| Multi-connection efficiency | Excellent | Good |
| Blocking behavior | Non-blocking | Blocking |
| Latency | ~10ms default | ~0ms |
| Best use case | Many concurrent tasks, low latency | Bulk publishing |

## Examples

Core pub/sub:

```bash
bundle exec ruby examples/core_lifecycle.rb
```

JetStream publish and pull:

```bash
bundle exec ruby examples/jetstream_roundtrip.rb
```

The integration spec boots the bundled [`bin/nats-server`](bin/nats-server) and runs these examples locally.

## Documentation

The documentation site is an Astro/Starlight project in [`docs-site`](docs-site).

```bash
npm --prefix docs-site install
bundle exec rake docs:dev
npm --prefix docs-site run build
```

## Development

```bash
bundle install
bundle exec rspec
rake build
```
