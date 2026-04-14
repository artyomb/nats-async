# frozen_string_literal: true

require "socket"
require "tempfile"
require "tmpdir"

module NatsServerHelper
  def project_path = File.expand_path("../..", __dir__)
  def server_path = File.join(project_path, "bin", "nats-server")
  def nats_server = RSpec.current_example.metadata.fetch(:nats_server_context)
  def nats_url = nats_server.fetch(:url)

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
          #{File.exist?(log_path) ? File.read(log_path) : '(log file missing)'}
          --- end nats-server log ---
        MSG
      end

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise <<~MSG
          bundled nats-server did not start on port #{port}
          --- nats-server log ---
          #{File.exist?(log_path) ? File.read(log_path) : '(log file missing)'}
          --- end nats-server log ---
        MSG
      end

      sleep 0.1
    end
  end

  def start_server_for(context)
    context[:pid] = Process.spawn(
      server_path,
      "-c", context.fetch(:config_path),
      "-js",
      "-sd", context.fetch(:store_dir),
      "-p", context.fetch(:port).to_s,
      out: context.fetch(:log),
      err: context.fetch(:log),
      chdir: project_path
    )
    wait_for_server(context.fetch(:port), context.fetch(:pid), context.fetch(:log_path))
    context.fetch(:pid)
  end

  def stop_server(pid)
    return unless pid

    Process.kill("TERM", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Process::Waiter::Error
    nil
  end

  def stop_current_server
    stop_server(nats_server[:pid])
    nats_server[:pid] = nil
  end

  def with_nats_server
    port = free_port
    Tempfile.create(["nats-async-example", ".log"]) do |log|
      Tempfile.create(["nats-async", ".conf"]) do |config|
        config.write("debug: true\ntrace: true\n")
        config.flush

        Dir.mktmpdir("nats-async-js") do |store_dir|
          context = {
            port: port,
            url: "nats://127.0.0.1:#{port}",
            log: log,
            log_path: log.path,
            config_path: config.path,
            store_dir: store_dir
          }

          begin
            start_server_for(context)
            yield context
          ensure
            stop_server(context[:pid])
          end
        end
      end
    end
  end

  def wait_async_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    until yield
      raise "condition was not met within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end
end

RSpec.configure do |config|
  config.include NatsServerHelper

  config.around(:example, :nats_server) do |example|
    with_nats_server do |context|
      example.metadata[:nats_server_context] = context
      example.run
    ensure
      example.metadata.delete(:nats_server_context)
    end
  end
end
