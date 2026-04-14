# nats-async

An async-compatible NATS client for Ruby using the Async gem for high-concurrency I/O.

## Features

- **Non-blocking I/O** using Async gem
- **High concurrency** - Handle thousands of concurrent connections
- **Thread-safe** publishing with configurable batch flushing
- **JetStream support**
- **Reconnection support**

## Performance

With `flush_batch_size` optimization, nats-async can **outperform nats-pure.rb**:

| Configuration | Throughput | Notes |
|--------------|------------|-------|
| nats-pure.rb (single-threaded) | ~500k msg/s | Baseline |
| nats-async (default, verbose=true) | ~10k msg/s | Heavy logging overhead |
| nats-async (verbose=false, batch=100) | ~300k msg/s | Production ready |
| **nats-async (batch=5000)** | **~550k msg/s** | **Best throughput** |

## Installation

Add to your Gemfile:

```ruby
gem 'nats-async'
```

## Usage

### Basic Publishing

```ruby
require 'async'
require 'nats-async'

Async do
  client = NatsAsync::Client.new(
    url: 'nats://127.0.0.1:4222',
    verbose: false,        # Critical for performance!
    flush_batch_size: 5000 # Flush every 5000 messages
  )
  client.start(task: Async::Task.current)
  
  1000.times do |i|
    client.publish('test.subject', "Message #{i}")
  end
  
  client.close
end
```

### High-Throughput Publishing

For maximum throughput, use:

```ruby
client = NatsAsync::Client.new(
  url: 'nats://127.0.0.1:4222',
  verbose: false,
  flush_batch_size: 5000  # Sweet spot for most workloads
)
```

### Receiving Messages

```ruby
client = NatsAsync::Client.new(url: 'nats://127.0.0.1:4222', verbose: false)
client.start(task: Async::Task.current)

client.subscribe('test.subject') do |msg|
  puts "Received: #{msg.data}"
end

sleep 5  # Keep alive
client.close
```

### Request/Reply

```ruby
client = NatsAsync::Client.new(url: 'nats://127.0.0.1:4222', verbose: false)
client.start(task: Async::Task.current)

response = client.request('echo', 'hello', timeout: 1)
puts "Response: #{response.data}"

client.close
```

### JetStream

```ruby
client = NatsAsync::Client.new(url: 'nats://127.0.0.1:4222', verbose: false)
client.start(task: Async::Task.current)

js = client.jetstream

# Publish to JetStream
js.publish('orders', 'order data', stream: 'orders')

# Subscribe to JetStream
js.subscribe('orders', stream: 'orders') do |msg|
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
| `flush_batch_size` | `100` | Flush socket every N messages (higher = more throughput) |
| `ping_interval` | `30` | Interval between ping messages |
| `ping_timeout` | `5` | Timeout for pong response |
| `tls` | `nil` | Enable TLS |
| `tls_verify` | `true` | Verify TLS certificates |

## Tuning Recommendations

1. **Disable logging in production**: `verbose: false` - This alone gives 10x+ improvement
2. **Use flush_batch_size=5000** for maximum throughput
3. **Use flush_batch_size=100** for lower latency requirements
4. **Never use flush_batch_size=1** in production - flushes every message

## Benchmarks

Run benchmarks:

```bash
bundle exec ruby benchmark_final.rb
```

Example output:

```
nats-pure.rb (single-threaded):  511288 msg/s
nats-async (opt., batch=5000):   545356 msg/s  ← 7% faster!
```

## Differences from nats-pure.rb

| Feature | nats-async | nats-pure.rb |
|---------|------------|--------------|
| Threading | Async (cooperative) | Ruby threads |
| Concurrency | Thousands of connections | Limited by threads |
| Single-threaded throughput | ~550k msg/s (optimized) | ~500k msg/s |
| Multi-connection efficiency | Excellent | Good |
| Blocking behavior | Non-blocking | Blocking |
| Best use case | Many concurrent tasks | Bulk publishing |

## License

Apache 2.0
