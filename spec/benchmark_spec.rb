# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require_relative "spec_helper"

if ENV.fetch("BENCHMARK", nil)
  require "async"
  require "benchmark"

  nats_pure_available = begin
    require "nats-pure"
    true
  rescue LoadError
    false
  end

  RSpec.describe "Benchmark", :nats_server do
    let(:test_subject) { "benchmark.throughput" }
    let(:message_count) { 10_000 }

    around do |example|
      skip "Install nats-pure to run benchmark specs" unless nats_pure_available

      example.run
    end

    def benchmark(&) = Benchmark.measure(&).real

    def pure_single_time
      benchmark do
        client = NATS.connect(nats_url)
        message_count.times { |i| client.publish(test_subject, "Msg #{i}") }
        client.close
      end
    end

    def pure_multi_time
      benchmark do
        client = NATS.connect(nats_url)
        threads = []
        msgs_per_thread = message_count / 16

        16.times do |i|
          threads << Thread.new do
            msgs_per_thread.times do |j|
              client.publish(test_subject, "Msg #{(i * msgs_per_thread) + j}")
            end
          end
        end

        threads.each(&:join)
        client.close
      end
    end

    def async_default_time
      benchmark do
        Async do
          client = NatsAsync::Client.new(url: nats_url, verbose: false)
          client.start(task: Async::Task.current)
          message_count.times { |i| client.publish(test_subject, "Msg #{i}") }
          client.close
        end
      end
    end

    def async_optimized_time
      benchmark do
        Async do
          client = NatsAsync::Client.new(
            url: nats_url,
            verbose: false,
            flush_delay: 0.05,
            flush_max_buffer: 5_000
          )
          client.start(task: Async::Task.current)
          message_count.times { |i| client.publish(test_subject, "Msg #{i}") }
          client.close
        end
      end
    end

    def async_aggressive_time
      benchmark do
        Async do
          client = NatsAsync::Client.new(
            url: nats_url,
            verbose: false,
            flush_delay: 0.01,
            flush_max_buffer: 10_000
          )
          client.start(task: Async::Task.current)
          message_count.times { |i| client.publish(test_subject, "Msg #{i}") }
          client.close
        end
      end
    end

    def throughput(time) = message_count / time

    def report(label, time)
      puts "\n#{label}: #{throughput(time).round(2)} msg/s"
    end

    def comparison_text(name, throughput, baseline)
      ratio = throughput / baseline
      relation = ratio >= 1 ? "#{ratio.round(2)}x faster" : "#{(1 / ratio).round(2)}x slower"
      "#{name}: #{relation} than nats-pure single-threaded"
    end

    it "reports nats-pure.rb single-threaded throughput" do
      time = pure_single_time

      expect(time).to be_positive
      report("nats-pure.rb (single-threaded)", time)
    end

    it "reports nats-pure.rb multi-threaded throughput" do
      time = pure_multi_time

      expect(time).to be_positive
      report("nats-pure.rb (multi-threaded)", time)
    end

    it "reports nats-async default throughput" do
      time = async_default_time

      expect(time).to be_positive
      report("nats-async (default, 10ms)", time)
    end

    it "reports nats-async optimized throughput" do
      time = async_optimized_time

      expect(time).to be_positive
      report("nats-async (optimized, 50ms)", time)
    end

    it "reports nats-async aggressive throughput" do
      time = async_aggressive_time

      expect(time).to be_positive
      report("nats-async (aggressive, 10ms)", time)
    end

    it "reports throughput summary" do
      pure_single_throughput = throughput(pure_single_time)
      pure_multi_throughput = throughput(pure_multi_time)
      async_default_throughput = throughput(async_default_time)
      async_optimized_throughput = throughput(async_optimized_time)

      puts "\n#{'=' * 60}"
      puts "RESULTS SUMMARY"
      puts "=" * 60
      puts "nats-pure.rb (single-threaded):   #{pure_single_throughput.round(2)} msg/s"
      puts "nats-pure.rb (multi-threaded):    #{pure_multi_throughput.round(2)} msg/s"
      puts "nats-async (default, 10ms):       #{async_default_throughput.round(2)} msg/s"
      puts "nats-async (optimized, 50ms):     #{async_optimized_throughput.round(2)} msg/s"
      puts "=" * 60
      puts "\nCOMPARISON"
      puts "-" * 60
      puts comparison_text("nats-async (10ms)", async_default_throughput, pure_single_throughput)
      puts comparison_text("nats-async (50ms)", async_optimized_throughput, pure_single_throughput)
      puts "=" * 60

      expect(async_optimized_throughput).to be_positive
    end
  end
end

# rubocop:enable RSpec/ExampleLength
