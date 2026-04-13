# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/NoExpectationExample
# rubocop:disable RSpec/DescribeClass

require_relative "spec_helper"

require "open3"
require "socket"
require "tempfile"
require "tmpdir"

RSpec.describe "example scripts" do
  def project_path = File.expand_path("..", __dir__)
  def server_path = File.join(project_path, "bin", "nats-server")

  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def wait_for_server(port, server_pid, log_path, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      socket = TCPSocket.new("127.0.0.1", port)
      socket.close
      return
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      if Process.waitpid(server_pid, Process::WNOHANG)
        raise <<~MSG
          bundled nats-server exited before becoming ready
          --- nats-server log ---
          #{File.exist?(log_path) ? File.read(log_path) : "(log file missing)"}
          --- end nats-server log ---
        MSG
      end

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise <<~MSG
          bundled nats-server did not start on port #{port}
          --- nats-server log ---
          #{File.exist?(log_path) ? File.read(log_path) : "(log file missing)"}
          --- end nats-server log ---
        MSG
      end

      sleep 0.1
    end
  end

  def start_server(port:, log:, config_path:, store_dir:)
    Process.spawn(
      server_path,
      "-c", config_path,
      "-js",
      "-sd", store_dir,
      "-p", port.to_s,
      out: log,
      err: log,
      chdir: project_path
    )
  end

  def stop_server(pid)
    Process.kill("TERM", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Process::Waiter::Error
    nil
  end

  def wait_async_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    until yield
      raise "condition was not met within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end

  def run_example(example_path, env)
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", example_path, chdir: project_path)
    return if status.success?

    raise <<~MSG
      example failed: #{example_path}
      status: #{status.exitstatus}
      stdout:
      #{stdout}
      stderr:
      #{stderr}
    MSG
  end

  it "runs the bundled examples against the local nats-server" do
    port = free_port
    url = "nats://127.0.0.1:#{port}"
    Tempfile.create(["nats-async-example", ".log"]) do |log|
      log_path = log.path
      Tempfile.create(["nats-async", ".conf"]) do |config|
        config.write("debug: true\ntrace: true\n")
        config.flush

        Dir.mktmpdir("nats-async-js") do |store_dir|
          server = Process.spawn(
            server_path,
            "-c", config.path,
            "-js",
            "-sd", store_dir,
            "-p", port.to_s,
            out: log,
            err: log,
            chdir: project_path
          )

          begin
            wait_for_server(port, server, log_path)
            run_example("examples/core_lifecycle.rb", {"NATS_URL" => url})
            run_example("examples/queue_group.rb", {"NATS_URL" => url})
            run_example("examples/request_reply.rb", {"NATS_URL" => url})
            run_example("examples/headers_and_binary.rb", {"NATS_URL" => url})
            run_example("examples/jetstream_management.rb", {"NATS_URL" => url})
            run_example("examples/jetstream_publish.rb", {"NATS_URL" => url})
            run_example("examples/backend_detection.rb", {"NATS_URL" => url})
            run_example("examples/jetstream_pull_consumer.rb", {"NATS_URL" => url})
            run_example(
              "examples/jetstream_roundtrip.rb",
              {
                "NATS_URL" => url,
                "JS_STREAM" => "spec_stream",
                "JS_SUBJECT" => "spec.subject",
                "JS_CONSUMER" => "spec_consumer",
                "JS_PAYLOAD" => "spec payload"
              }
            )
          ensure
            begin
              Process.kill("TERM", server)
              Process.wait(server)
            rescue Errno::ESRCH, Process::Waiter::Error
              nil
            end
          end
        end
      end
    end
  end

  it "reconnects and replays subscriptions" do
    port = free_port
    url = "nats://127.0.0.1:#{port}"
    Tempfile.create(["nats-async-reconnect", ".log"]) do |log|
      log_path = log.path
      Tempfile.create(["nats-async", ".conf"]) do |config|
        config.write("debug: true\ntrace: true\n")
        config.flush

        Dir.mktmpdir("nats-async-js") do |store_dir|
          server = start_server(port: port, log: log, config_path: config.path, store_dir: store_dir)
          wait_for_server(port, server, log_path)

          Async do |task|
            client = NatsAsync::Client.new(
              url: url,
              verbose: false,
              reconnect: true,
              reconnect_interval: 0.05,
              ping_interval: 0.05,
              ping_timeout: 0.05
            )
            messages = []
            condition = Async::Condition.new
            client.start(task: task)
            client.subscribe("reconnect.demo") do |message|
              messages << message.data
              condition.signal
            end

            client.publish("reconnect.demo", "before")
            condition.wait until messages.include?("before")

            stop_server(server)
            wait_async_until { client.status == :reconnecting || client.status == :disconnected }

            server = start_server(port: port, log: log, config_path: config.path, store_dir: store_dir)
            wait_for_server(port, server, log_path)
            wait_async_until { client.connected? }

            client.publish("reconnect.demo", "after")
            condition.wait until messages.include?("after")

            expect(messages).to include("before", "after")
          ensure
            client&.close
            stop_server(server)
          end
        end
      end
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/NoExpectationExample
# rubocop:enable RSpec/DescribeClass
