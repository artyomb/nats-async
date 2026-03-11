# Nats Async

`nats-async` packages the `nats-test` prototype as a Ruby gem with the same project layout and build flow as `dry-stack`.

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

```ruby
require "nats-async"

connector = NatsAsync::SimpleConnector.new(url: "nats://127.0.0.1:4222", verbose: false)
connector.run(duration: 1) do |client, task|
  client.subscribe("demo.subject") do |message|
    puts "received: #{message.data}"
    task.stop
  end

  client.publish("demo.subject", "hello")
end
```

## Examples

Core pub/sub:

```bash
bundle exec ruby examples/basic_pub_sub.rb
```

JetStream publish and pull:

```bash
bundle exec ruby examples/jetstream_roundtrip.rb
```

The integration spec boots the bundled [`bin/nats-server`](bin/nats-server) and runs these examples locally.

## Development

```bash
bundle install
bundle exec rspec
rake build
```
