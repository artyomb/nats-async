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
  def config_path = File.join(project_path, "config", "nats.conf")

  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def wait_for_server(port, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      socket = TCPSocket.new("127.0.0.1", port)
      socket.close
      return
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      raise "nats-server did not start on port #{port}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.1
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
      Dir.mktmpdir("nats-async-js") do |store_dir|
        server = Process.spawn(
          server_path,
          "-c", config_path,
          "-js",
          "-sd", store_dir,
          "-p", port.to_s,
          out: log,
          err: log,
          chdir: project_path
        )

        begin
          wait_for_server(port)
          run_example("examples/basic_pub_sub.rb", {"NATS_URL" => url})
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

# rubocop:enable RSpec/ExampleLength, RSpec/NoExpectationExample
# rubocop:enable RSpec/DescribeClass
