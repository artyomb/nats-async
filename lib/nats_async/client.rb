# frozen_string_literal: true

require "async"
require "async/condition"
require "async/queue"
ENV["CONSOLE_OUTPUT"] ||= "XTerm"
require "console"
require "json"
require "securerandom"
require "timeout"

require_relative "connection"
require_relative "errors"
require_relative "message"

module NatsAsync
  class Client
    AckError = NatsAsync::AckError
    ConnectionError = NatsAsync::ConnectionError
    MsgAlreadyAcked = NatsAsync::MsgAlreadyAcked
    NotAckable = NatsAsync::NotAckable
    RequestError = NatsAsync::RequestError
    ProtocolError = NatsAsync::ProtocolError
    Message = NatsAsync::Message

    class RequestPromise
      attr_reader :id, :status, :error

      def initialize(id:)
        @id = id
        @status = :pending
        @condition = Async::Condition.new
        @value = nil
        @error = nil
      end

      def pending? = @status == :pending

      def fulfilled? = @status == :fulfilled

      def rejected? = @status == :rejected

      def wait(timeout: nil)
        wait_for_completion(timeout: timeout) if pending?
        raise @error if rejected?

        @value
      end

      def value
        return @value if fulfilled?
        raise @error if rejected?

        nil
      end

      def fulfill(value)
        return false unless pending?

        @value = value
        @status = :fulfilled
        @condition.signal
        true
      end

      def reject(error)
        return false unless pending?

        @error = error
        @status = :rejected
        @condition.signal
        true
      end

      def to_s
        "#<#{self.class.name} id=#{id} status=#{status}>"
      end

      alias_method :inspect, :to_s

      private

      def wait_for_completion(timeout:)
        if timeout
          Async::Task.current.with_timeout(timeout) { @condition.wait while pending? }
        else
          @condition.wait while pending?
        end
      rescue Timeout::Error, Async::TimeoutError
        raise Timeout::Error, "timeout waiting for request promise #{id} after #{timeout}s"
      end
    end

    def initialize(
      url: "nats://127.0.0.1:4222",
      verbose: true,
      js_api_prefix: "$JS.API",
      ping_interval: 30,
      ping_timeout: 5,
      tls: nil,
      tls_verify: true,
      tls_ca_file: nil,
      tls_ca_path: nil,
      tls_hostname: nil,
      tls_handshake_first: false,
      user: nil,
      password: nil,
      nkey_seed: nil,
      nkey_seed_file: nil,
      nkey_public_key: nil,
      reconnect: false,
      reconnect_interval: 1,
      max_reconnect_attempts: nil,
      flush_delay: 0.01,
      flush_max_buffer: 5000
    )
      @js_api_prefix = normalize_subject_prefix(js_api_prefix)
      @ping_interval = ping_interval
      @ping_timeout = ping_timeout
      @reconnect = reconnect
      @reconnect_interval = reconnect_interval
      @max_reconnect_attempts = max_reconnect_attempts
      @logger = Console.logger.with(level: (verbose ? :debug : :error), verbose: false)
      @connection_options = {
        url: url,
        logger: @logger,
        tls: tls,
        tls_verify: tls_verify,
        tls_ca_file: tls_ca_file,
        tls_ca_path: tls_ca_path,
        tls_hostname: tls_hostname,
        tls_handshake_first: tls_handshake_first,
        user: user,
        password: password,
        nkey_seed: nkey_seed,
        nkey_seed_file: nkey_seed_file,
        nkey_public_key: nkey_public_key,
        flush_delay: flush_delay,
        flush_max_buffer: flush_max_buffer
      }
      @connection = build_connection

      @ping_task = nil
      @reconnect_task = nil
      @request_timeout_task = nil
      @request_callback_task = nil
      @request_callback_queue = nil
      @read_error = nil
      @started = false
      @closed = true
      @status = :closed
      @sid_seq = 0
      @request_seq = 0
      @subscriptions = {}
      @pending_requests = {}
      @pending_request_condition = Async::Condition.new

      # Response multiplexing state
      @resp_mux_prefix = nil
      @resp_mux_subsid = nil
      @resp_mux_lock = Async::Semaphore.new(1)
      @resp_map = {}
      @resp_map_lock = Async::Semaphore.new(1)
    end

    attr_reader :js_api_prefix, :status

    def start(task:)
      return self if connected?

      @reactor_task = task
      @status = :connecting
      @connection.start(task: task)
      @started = true
      @closed = false
      ping!(timeout: @ping_timeout)
      @status = :connected
      start_ping_loop(task)
      start_request_timeout_loop(task)
      start_request_callback_loop(task)
      self
    rescue StandardError
      stop
      @started = false
      @closed = true
      @status = :closed
      raise
    end

    def close
      return true if closed?

      @closed = true
      stop
      @started = false
      @status = :closed
      true
    end

    def resolve_backend(mode: :auto, stream: nil)
      mode = mode.to_sym
      return :core if mode == :core

      raise ArgumentError, "stream is required for #{mode} backend" if stream.to_s.empty?

      case mode
      when :jetstream
        jetstream.stream_info(stream)
        :jetstream
      when :auto
        jetstream.stream_exists?(stream) ? :jetstream : :core
      else
        raise ArgumentError, "unsupported backend mode: #{mode.inspect}"
      end
    rescue JetStream::Error
      raise if mode == :jetstream

      :core
    end

    def drain(timeout: 5)
      @ping_task&.stop
      @ping_task = nil
      flush(timeout: timeout) if connected?
      true
    ensure
      close
    end

    def stop
      @request_timeout_task&.stop
      close_error = IOError.new("client closed")
      reject_pending_requests(close_error)
      reject_queued_request_callbacks(close_error)
      @request_callback_task&.stop
      @ping_task&.stop
      @reconnect_task&.stop
      cleanup_resp_mux
      @connection.close
      @request_timeout_task = nil
      @request_callback_task = nil
      @request_callback_queue = nil
      @ping_task = nil
      @reconnect_task = nil
    end

    # Clean up the response multiplexing subscription
    def cleanup_resp_mux
      return unless @resp_mux_subsid

      @resp_mux_lock.acquire do
        @subscriptions.delete(@resp_mux_subsid)
        safe_unsubscribe(@resp_mux_subsid)
        @resp_mux_subsid = nil
        @resp_mux_prefix = nil
        @resp_map.clear
      end
    end

    def flush(timeout: 2)
      ping!(timeout: timeout)
      true
    end

    def connected?
      @status == :connected && @started && !@closed && @connection.connected?
    end

    def closed?
      @closed
    end

    def last_error
      @read_error || @connection.last_error
    end

    def ping!(timeout: 2)
      @connection.ping!(timeout: timeout)
    end

    def publish(subject, payload = "", reply: nil, headers: nil)
      ensure_connected!
      @connection.publish(subject, payload, reply: reply, headers: headers)
    end

    def subscribe(subject, queue: nil, handler: nil, &block)
      ensure_open!
      callback = handler || block
      raise ArgumentError, "handler or block required for subscribe" unless callback

      sid = next_sid
      @subscriptions[sid] = {subject: subject, queue: queue, callback: callback}
      @connection.subscribe(subject, sid: sid, queue: queue) if connected?
      sid
    end

    # Ensure the response multiplexing subscription is set up
    # Creates a single wildcard subscription to handle all request responses
    def ensure_resp_mux_sub!(task:)
      return if @resp_mux_prefix

      @resp_mux_lock.acquire do
        return if @resp_mux_prefix

        # Generate unique prefix for this connection
        @resp_mux_prefix = "_INBOX.#{SecureRandom.hex(8)}"

        # Create wildcard subscription to handle all responses
        # Messages for request replies come with subject = the reply inbox
        @resp_mux_subsid = subscribe("#{@resp_mux_prefix}.*") do |msg|
          # Extract token from subject (format: _INBOX.<prefix>.<token>)
          token = msg.subject.split(".").last
          process_mux_response(token, msg)
        end
      end

      # Flush immediately to ensure subscription is registered before any requests
      @connection.flush_pending
      # The flush is async, so we just wait a tiny bit to ensure it's sent
      sleep(0.001)
    end

    # Process a response message from the multiplexed subscription
    def process_mux_response(token, message)
      @resp_map_lock.acquire do
        pending = @resp_map.delete(token)
        return unless pending

        if pending[:callback]
          enqueue_request_callback(pending, message)
        else
          pending[:promise].fulfill(message)
        end
      rescue StandardError
        @logger.error("mux response handler error")
      end
    end

    # Generate a unique token for request tracking
    def generate_resp_token
      SecureRandom.hex(8)
    end

    def unsubscribe(sid)
      @subscriptions.delete(sid)
      @connection.unsubscribe(sid)
      true
    end

    def received_pings = @connection.received_pings

    def received_pongs = @connection.received_pongs

    def sent_pings = @connection.sent_pings

    def server_info = @connection.server_info

    def request(subject, payload = "", timeout: 0.5, headers: nil, &block)
      ensure_connected!

      # If block is provided, use old-style per-request subscription
      if block
        return request_old_style(subject, payload, timeout: timeout, headers: headers, &block)
      end

      # Use multiplexed subscription for promise-based requests
      ensure_resp_mux_sub!(task: @reactor_task)
      token = generate_resp_token
      inbox = "#{@resp_mux_prefix}.#{token}"

      promise = RequestPromise.new(id: token)

      begin
        # Track request with token-based lookup in mux response handler
        @resp_map_lock.acquire do
          @resp_map[token] = {
            promise: promise,
            deadline: monotonic_now + timeout,
            timeout: timeout,
            callback: nil
          }
        end
        @pending_request_condition.signal

        publish(subject, request_payload(payload), reply: inbox, headers: headers)
        promise
      rescue StandardError
        @resp_map_lock.acquire do
          @resp_map.delete(token)
        end
        raise
      end
    end

    def request_old_style(subject, payload = "", timeout: 0.5, headers: nil, &block)
      # Old-style request with per-request subscription (for callback support)
      request_id = next_request_id
      promise = RequestPromise.new(id: request_id)
      inbox = request_inbox(request_id)
      sid = nil

      sid = subscribe(inbox, handler: lambda { |message| complete_request(request_id, message) })
      track_request(request_id, subject: subject, sid: sid, promise: promise, timeout: timeout, callback: block)
      publish(subject, request_payload(payload), reply: inbox, headers: headers)
      promise
    rescue StandardError => e
      reject_request_setup(request_id: request_id, promise: promise, sid: sid, error: e)
    end

    def js_api_subject(*tokens)
      [js_api_prefix, *tokens.flatten].compact.map(&:to_s).reject(&:empty?).join(".")
    end

    def jetstream
      @jetstream ||= JetStream.new(self)
    end

    private

    def start_ping_loop(task)
      return unless @ping_interval&.positive?

      @ping_task = task.async { |ping_task| ping_loop(ping_task) }
    end

    def start_request_timeout_loop(task)
      @request_timeout_task = task.async { |timeout_task| request_timeout_loop(timeout_task) }
    end

    def start_request_callback_loop(task)
      @request_callback_queue = Async::Queue.new
      @request_callback_task = task.async { request_callback_loop }
    end

    def build_connection
      Connection.new(
        **@connection_options,
        on_message: method(:dispatch_message),
        on_error: method(:connection_error)
      )
    end

    def ping_loop(task)
      loop do
        sleep(@ping_interval)
        next unless connected?

        ping!(timeout: @ping_timeout)
      end
    rescue StandardError => e
      @read_error ||= e
      @logger.error("ping loop error: #{e.class}: #{e.message}")
      @connection.close
      connection_error(e)
    end

    def request_timeout_loop(task)
      loop do
        expire_pending_requests
        interval = next_request_timeout_interval
        if interval
          task.with_timeout(interval) { @pending_request_condition.wait }
        else
          @pending_request_condition.wait
        end
      rescue Timeout::Error, Async::TimeoutError
        next
      end
    rescue StandardError => e
      @logger.error("request timeout loop error: #{e.class}: #{e.message}")
    end

    def request_callback_loop
      while (job = @request_callback_queue.dequeue)
        run_request_callback(**job)
      end
    rescue StandardError => e
      @logger.error("request callback loop error: #{e.class}: #{e.message}")
    end

    def connection_error(error)
      return if closed?

      @read_error = error
      reject_pending_requests(error)
      @status = @reconnect ? :reconnecting : :disconnected
      @logger.error("connection error: #{error.class}: #{error.message}") unless @reconnect
      start_reconnect_loop if @reconnect
    end

    def start_reconnect_loop
      return if @reconnect_task || !@reactor_task

      @reconnect_task = @reactor_task.async { |task| reconnect_loop(task) }
    end

    def reconnect_loop(task)
      attempts = 0

      until closed?
        break if @max_reconnect_attempts && attempts >= @max_reconnect_attempts

        attempts += 1
        sleep(@reconnect_interval) if @reconnect_interval&.positive?

        begin
          reconnect_once(task)
          return
        rescue StandardError => e
          @read_error = e
          @logger.error("reconnect attempt #{attempts} failed: #{e.class}: #{e.message}")
        end
      end

      @status = :disconnected unless closed?
    ensure
      @reconnect_task = nil
    end

    def reconnect_once(task)
      @connection.close
      @connection = build_connection
      @connection.start(task: @reactor_task || task)
      @connection.ping!(timeout: @ping_timeout)
      replay_subscriptions
      reset_resp_mux # Reset mux on reconnect since prefix changes
      @read_error = nil
      @status = :connected
      true
    end

    def replay_subscriptions
      @subscriptions.each do |sid, subscription|
        # Skip the mux subscription - it will be re-created on first request
        next if sid == @resp_mux_subsid
        @connection.subscribe(subscription[:subject], sid: sid, queue: subscription[:queue])
      end
    end

    # Reset response multiplexing state after reconnect
    def reset_resp_mux
      @resp_mux_lock.acquire do
        # Remove old mux subscription from tracking (don't UNSUB since socket is already closed)
        @subscriptions.delete(@resp_mux_subsid) if @resp_mux_subsid
        @resp_mux_subsid = nil
        @resp_mux_prefix = nil
        @resp_map.clear
      end
    end

    def ensure_connected!
      return if connected?

      raise ConnectionError, "client is not connected (status=#{status})"
    end

    def ensure_open!
      raise ConnectionError, "client is closed" if closed?
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def request_payload(payload)
      return "" if payload.nil?
      return payload if payload.is_a?(String)

      JSON.generate(payload)
    end

    def request_inbox(request_id)
      "_INBOX.#{rand(1 << 30)}.#{request_id}"
    end

    def track_request(request_id, subject:, sid:, promise:, timeout:, callback:)
      @pending_requests[request_id] = {
        subject: subject,
        sid: sid,
        promise: promise,
        deadline: monotonic_now + timeout,
        timeout: timeout,
        callback: callback
      }
      @pending_request_condition.signal
    end

    def reject_request_setup(request_id:, promise:, sid:, error:)
      @pending_requests.delete(request_id) if request_id
      promise&.reject(error)
      safe_unsubscribe(sid) if sid
      promise || raise(error)
    end

    def complete_request(request_id, message)
      pending = @pending_requests.delete(request_id)
      return unless pending

      if pending[:callback]
        enqueue_request_callback(pending, message)
      else
        pending[:promise].fulfill(message)
      end
      safe_unsubscribe(pending[:sid])
    end

    def enqueue_request_callback(pending, message)
      @request_callback_queue.enqueue({callback: pending[:callback], promise: pending[:promise], message: message})
    rescue StandardError => e
      pending[:promise].reject(e)
      @logger.error("request callback enqueue error: #{e.class}: #{e.message}")
    end

    def run_request_callback(callback:, promise:, message:)
      callback.call(message)
      promise.fulfill(message)
    rescue StandardError => e
      promise.reject(e)
      @logger.error("request callback error: #{e.class}: #{e.message}")
    end

    def expire_pending_requests
      now = monotonic_now

      # Expire old-style requests from @pending_requests
      @pending_requests.each_key.to_a.each do |request_id|
        pending = @pending_requests[request_id]
        next unless pending && pending[:deadline] <= now

        reject_pending_request(request_id, Timeout::Error.new("request timeout after #{pending[:timeout]}s"), unsubscribe: true)
      end

      # Expire mux-based requests from @resp_map
      @resp_map_lock.acquire do
        @resp_map.each_key.to_a.each do |token|
          pending = @resp_map[token]
          next unless pending && pending[:deadline] <= now

          reject_mux_request(token, Timeout::Error.new("request timeout after #{pending[:timeout]}s"))
          @resp_map.delete(token)
        end
      end
    end

    def next_request_timeout_interval
      # Check both old-style and mux-based requests
      deadlines = []

      @pending_requests.each_value do |pending|
        next unless pending[:deadline]
        deadlines << pending[:deadline]
      end

      @resp_map_lock.acquire do
        @resp_map.each_value do |pending|
          next unless pending[:deadline]
          deadlines << pending[:deadline]
        end
      end

      return unless deadlines.any?

      [deadlines.min - monotonic_now, 0].max
    end

    def reject_mux_request(token, error)
      pending = @resp_map[token]
      return unless pending

      pending[:promise].reject(error)
    end

    def reject_pending_requests(error)
      @pending_requests.each_key.to_a.each do |request_id|
        reject_pending_request(request_id, error, unsubscribe: false)
      end

      # Also reject mux-based requests
      @resp_map_lock.acquire do
        @resp_map.each_key.to_a.each do |token|
          pending = @resp_map.delete(token)
          pending[:promise].reject(error) if pending
        end
      end
    end

    def reject_queued_request_callbacks(error)
      return unless @request_callback_queue

      while (job = @request_callback_queue.dequeue(timeout: 0))
        job[:promise].reject(error)
      end
    rescue StandardError => e
      @logger.error("request callback cleanup error: #{e.class}: #{e.message}")
    end

    def reject_pending_request(request_id, error, unsubscribe:)
      pending = @pending_requests.delete(request_id)
      return unless pending

      pending[:promise].reject(error)
      unsubscribe ? safe_unsubscribe(pending[:sid]) : @subscriptions.delete(pending[:sid])
    end

    def next_sid
      @sid_seq += 1
    end

    def next_request_id
      @request_seq += 1
    end

    def dispatch_message(message)
      handler = @subscriptions.dig(message.sid, :callback)

      if handler
        handler.call(message)
      else
        @logger.warn("no subscription handler for sid=#{message.sid}")
      end
    rescue StandardError => e
      @logger.error("subscription handler error: #{e.class}: #{e.message}")
    end

    def safe_unsubscribe(sid)
      unsubscribe(sid)
    rescue StandardError => e
      @subscriptions.delete(sid)
      @logger.error("unsubscribe cleanup error: #{e.class}: #{e.message}")
    end

    def normalize_subject_prefix(value)
      prefix = value.to_s.strip.sub(/\.+\z/, "")
      raise ArgumentError, "js_api_prefix cannot be empty" if prefix.empty?

      prefix
    end
  end
end
