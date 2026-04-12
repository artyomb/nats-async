# frozen_string_literal: true

require "async"
require "async/condition"
require "async/semaphore"
ENV["CONSOLE_OUTPUT"] ||= "XTerm"
require "console"
require "io/endpoint"
require "io/endpoint/host_endpoint"
require "io/stream"
require "json"
require "timeout"
require "uri"
require "base64"
require "openssl"

module NatsAsync
  class Client
    CR_LF = "\r\n"
    HEADER_LINE = "NATS/1.0"

    class AckError < StandardError; end
    class MsgAlreadyAcked < AckError; end
    class NotAckable < AckError; end
    class RequestError < StandardError; end
    class ResponseParseError < RequestError; end
    class ProtocolError < StandardError; end

    class Headers < Hash
      def self.wrap(values)
        new.tap { |headers| values.each { |key, value| headers[key] = value } }
      end

      def [](key)
        return super if key?(key)

        match = keys.find { |existing| existing.to_s.casecmp?(key.to_s) }
        match ? super(match) : nil
      end
    end

    class Message
      ACK = "+ACK"
      NAK = "-NAK"
      TERM = "+TERM"
      WPI = "+WPI"

      attr_reader :subject, :sid, :reply, :data, :headers
      alias header headers

      def initialize(subject:, sid:, reply:, data:, connector:, headers: {})
        @subject = subject
        @sid = sid
        @reply = reply
        @data = data
        @headers = Headers.wrap(headers)
        @connector = connector
        @acked = false
      end

      def ack(**_params) = finalize_ack!(ACK)

      def ack_sync(timeout: 0.5, **_params) = finalize_ack!(ACK, timeout: timeout)

      def nak(delay: nil, timeout: nil, **_params)
        payload = delay ? "#{NAK} #{{delay: delay}.to_json}" : NAK
        finalize_ack!(payload, timeout: timeout)
      end

      def term(timeout: nil, **_params) = finalize_ack!(TERM, timeout: timeout)

      def in_progress(timeout: nil, **_params)
        ensure_reply!
        publish_ack(WPI, timeout: timeout)
      end

      def ackable?
        !reply.to_s.empty?
      end

      def acked?
        @acked
      end

      def metadata
        return unless reply&.start_with?("$JS.ACK.")

        tokens = reply.split(".")
        return if tokens.size < 9

        if tokens.size >= 12
          domain = tokens[2] == "_" ? "" : tokens[2]
          stream = tokens[4]
          consumer = tokens[5]
          delivered = tokens[6].to_i
          stream_seq = tokens[7].to_i
          consumer_seq = tokens[8].to_i
          timestamp_ns = tokens[9].to_i
          pending = tokens[10].to_i
        else
          domain = ""
          stream = tokens[2]
          consumer = tokens[3]
          delivered = tokens[4].to_i
          stream_seq = tokens[5].to_i
          consumer_seq = tokens[6].to_i
          timestamp_ns = tokens[7].to_i
          pending = tokens[8].to_i
        end

        {
          stream: stream,
          consumer: consumer,
          delivered: delivered,
          sequence: {stream: stream_seq, consumer: consumer_seq},
          timestamp_ns: timestamp_ns,
          pending: pending,
          domain: domain
        }
      end

      private

      def finalize_ack!(payload, timeout: nil)
        raise MsgAlreadyAcked, "message already acknowledged" if @acked

        publish_ack(payload, timeout: timeout)
        @acked = true
        true
      end

      def publish_ack(payload, timeout: nil)
        ensure_reply!
        @connector.publish(@reply, payload)
      end

      def ensure_reply!
        raise NotAckable, "message has no reply subject" if reply.nil? || reply.empty?
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
      nkey_public_key: nil
    )
      @url = URI(url)
      @verbose = verbose
      @js_api_prefix = normalize_subject_prefix(js_api_prefix)
      @ping_interval = ping_interval
      @ping_timeout = ping_timeout
      @tls_enabled = tls.nil? ? %w[tls nats+tls].include?(@url.scheme) : tls
      @tls_verify = tls_verify
      @tls_ca_file = presence(tls_ca_file)
      @tls_ca_path = presence(tls_ca_path)
      @tls_hostname = presence(tls_hostname)
      @tls_handshake_first = tls_handshake_first
      @auth_user = presence(user || @url.user)
      @auth_password = presence(password || @url.password)
      @nkey_seed = presence(nkey_seed)
      @nkey_seed_file = presence(nkey_seed_file)
      @nkey_public_key = presence(nkey_public_key)
      @stream = nil
      @logger = Console.logger.with(level: (verbose ? :debug : :error), verbose: false)

      @received_pings = 0
      @received_pongs = 0
      @sent_pings = 0
      @server_info = nil

      @read_task = nil
      @ping_task = nil
      @read_error = nil
      @started = false
      @closed = true
      @write_lock = Async::Semaphore.new(1)
      @pong_condition = Async::Condition.new
      @sid_seq = 0
      @subscriptions = {}
    end

    attr_reader :received_pings, :received_pongs, :sent_pings, :server_info, :js_api_prefix

    def start(task:)
      return self if connected?

      connect!
      read_initial_info!
      send_connect!
      @read_task = task.async { read_loop }
      @started = true
      @closed = false
      ping!(timeout: @ping_timeout)
      start_ping_loop(task)
      self
    rescue StandardError
      stop
      @started = false
      @closed = true
      raise
    end

    def close
      return true if closed?

      stop
      @started = false
      @closed = true
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
      @ping_task&.stop
      @read_task&.stop
      safe_close_stream
      @ping_task = nil
      @read_task = nil
    end

    def flush(timeout: 2)
      ping!(timeout: timeout)
      true
    end

    def connected?
      @started && !@closed && !@stream.nil?
    end

    def closed?
      @closed
    end

    def last_error
      @read_error
    end

    def ping!(timeout: 2)
      expected_pongs = @received_pongs + 1

      @sent_pings += 1
      write_line("PING")
      await(timeout: timeout, condition: @pong_condition, timeout_message: "timeout waiting for PONG after #{timeout}s", predicate: lambda {
        raise @read_error if @read_error
        @received_pongs >= expected_pongs
      })
    end

    def publish(subject, payload = "", reply: nil, headers: nil)
      payload = payload.to_s
      return publish_with_headers(subject, payload, headers, reply: reply) if headers && !headers.empty?

      command = build_pub_command(subject, payload.bytesize, reply: reply)
      @logger.debug("C->S #{command}")

      @write_lock.acquire do
        @stream.write("#{command}#{CR_LF}", flush: false)
        @stream.write(payload, flush: false)
        @stream.write(CR_LF, flush: true)
      end
      protocol_payload_out(payload)
    end

    def subscribe(subject, queue: nil, handler: nil, &block)
      callback = handler || block
      raise ArgumentError, "handler or block required for subscribe" unless callback

      sid = next_sid
      @subscriptions[sid] = callback
      command = queue ? "SUB #{subject} #{queue} #{sid}" : "SUB #{subject} #{sid}"
      write_line(command)
      sid
    end

    def unsubscribe(sid)
      write_line("UNSUB #{sid}")
      @subscriptions.delete(sid)
      true
    end

    def request(subject, payload = "", timeout: 0.5, parse_json: false, headers: nil)
      response = request_message(subject, payload, timeout: timeout, headers: headers)
      result = parse_json ? parse_json_response(subject, response.data) : response.data
      ensure_request_ok!(subject, result) if parse_json
      block_given? ? yield(result) : result
    end

    def request_message(subject, payload = "", timeout: 0.5, headers: nil)
      inbox = "_INBOX.#{rand(1 << 30)}.#{next_sid}"
      response = nil
      condition = Async::Condition.new
      on_response = ->(msg) { response = msg; condition.signal }
      with_temp_subscription(inbox, handler: on_response) do
        publish(subject, request_payload(payload), reply: inbox, headers: headers)
        await(timeout: timeout, condition: condition, timeout_message: "request timeout after #{timeout}s", predicate: lambda {
          raise @read_error if @read_error
          !response.nil?
        })
      end

      block_given? ? yield(response) : response
    end

    def js_api_subject(*tokens)
      [js_api_prefix, *tokens.flatten].compact.map(&:to_s).reject(&:empty?).join(".")
    end

    def jetstream
      @jetstream ||= JetStream.new(self)
    end

    private

    def start_ping_loop(task)
      return unless @ping_interval && @ping_interval.positive?

      @ping_task = task.async { |ping_task| ping_loop(ping_task) }
    end

    def ping_loop(task)
      loop do
        task.sleep(@ping_interval)
        ping!(timeout: @ping_timeout)
      end
    rescue StandardError => e
      @read_error ||= e
      @logger.error("ping loop error: #{e.class}: #{e.message}")
      safe_close_stream
    end

    def connect!
      host = @url.host || "127.0.0.1"
      port = @url.port || 4222
      socket = IO::Endpoint.tcp(host, port).connect
      @stream = IO.Stream(socket)

      return unless @tls_enabled

      @server_info = parse_info_line(read_line) unless @tls_handshake_first
      socket = wrap_tls_socket(socket, host)
      @stream = IO.Stream(socket)
    end

    def read_initial_info!
      return if @server_info

      @server_info = parse_info_line(read_line)
    end

    def send_connect!
      payload = {
        verbose: false,
        pedantic: false,
        tls_required: @tls_enabled,
        lang: "ruby",
        version: "nats-async-playground",
        protocol: 1,
        headers: true,
        echo: true
      }
      payload.merge!(auth_connect_fields)

      write_line("CONNECT #{JSON.generate(payload)}")
    end

    def read_loop
      loop do
        line = read_line
        case line
        when "PING"
          @received_pings += 1
          write_line("PONG")
        when "PONG"
          @received_pongs += 1
          @pong_condition.signal
        when /\A-ERR\s+/
          raise ProtocolError, "server error: #{line}"
        when /\AINFO\s+/
          @server_info = parse_info_line(line)
        when /\AHMSG\s+/
          dispatch_hmsg(line)
        when /\AMSG\s+/
          dispatch_msg(line)
        end
      end
    rescue StandardError => e
      @read_error = e
      @logger.error("read loop error: #{e.class}: #{e.message}")
    end

    def write_line(data)
      @write_lock.acquire do
        @stream.write("#{data}#{CR_LF}", flush: true)
      end
      @logger.debug("C->S #{data}")
    end

    def read_line
      data = @stream.read_until(CR_LF, chomp: true)
      raise EOFError, "socket closed" unless data

      @logger.debug("S->C #{data}")
      data
    end

    def await(timeout:, condition:, timeout_message:, predicate:)
      return true if predicate.call

      deadline = monotonic_now + timeout
      until predicate.call
        remaining = deadline - monotonic_now
        raise Timeout::Error, timeout_message if remaining <= 0

        Async::Task.current.with_timeout(remaining) { condition.wait }
      end

      true
    rescue Timeout::Error
      raise Timeout::Error, timeout_message
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def request_payload(payload)
      return "" if payload.nil?
      return payload if payload.is_a?(String)

      JSON.generate(payload)
    end

    def ensure_request_ok!(subject, result)
      return result unless result.is_a?(Hash) && result[:error]

      error = result[:error]
      description = error.is_a?(Hash) ? error[:description] || error[:code] || error.inspect : error
      raise RequestError, "request failed for #{subject}: #{description}"
    end

    def parse_json_response(subject, data)
      JSON.parse(data, symbolize_names: true)
    rescue JSON::ParserError => e
      raise ResponseParseError, "request failed for #{subject}: invalid JSON response (#{e.message})"
    end

    def parse_info_line(line)
      raise ProtocolError, "expected INFO, got: #{line.inspect}" unless line.start_with?("INFO ")

      JSON.parse(line.delete_prefix("INFO "), symbolize_names: true)
    rescue JSON::ParserError => e
      raise ProtocolError, "invalid INFO payload: #{e.message}"
    end

    def next_sid
      @sid_seq += 1
    end

    def dispatch_msg(control_line)
      subject, sid, reply, size = parse_msg_control_line(control_line)
      payload = @stream.read_exactly(size)
      suffix = @stream.read_exactly(CR_LF.bytesize)
      raise ProtocolError, "malformed MSG payload ending: #{suffix.inspect}" unless suffix == CR_LF

      dispatch_message(Message.new(subject: subject, sid: sid, reply: reply, data: payload, connector: self))
    rescue StandardError => e
      @logger.error("message dispatch error: #{e.class}: #{e.message}")
    end

    def dispatch_hmsg(control_line)
      subject, sid, reply, header_size, total_size = parse_hmsg_control_line(control_line)
      raise ProtocolError, "HMSG header size exceeds total size" if header_size > total_size

      data = @stream.read_exactly(total_size)
      suffix = @stream.read_exactly(CR_LF.bytesize)
      raise ProtocolError, "malformed HMSG payload ending: #{suffix.inspect}" unless suffix == CR_LF

      header_block = data.byteslice(0, header_size) || +""
      payload = data.byteslice(header_size, total_size - header_size) || +""
      headers = parse_header_block(header_block)
      dispatch_message(Message.new(subject: subject, sid: sid, reply: reply, data: payload, connector: self, headers: headers))
    rescue StandardError => e
      @logger.error("header message dispatch error: #{e.class}: #{e.message}")
    end

    def dispatch_message(message)
      handler = @subscriptions[message.sid]
      protocol_payload_in(message.data)

      if handler
        handler.call(message)
      else
        @logger.warn("no subscription handler for sid=#{message.sid}")
      end
    end

    def parse_msg_control_line(control_line)
      tokens = control_line.split(" ")
      raise ProtocolError, "malformed MSG line: #{control_line.inspect}" unless tokens.first == "MSG"

      case tokens.length
      when 4
        [tokens[1], Integer(tokens[2]), nil, Integer(tokens[3])]
      when 5
        [tokens[1], Integer(tokens[2]), tokens[3], Integer(tokens[4])]
      else
        raise ProtocolError, "unexpected MSG control tokens: #{tokens.length}"
      end
    rescue ArgumentError => e
      raise ProtocolError, "invalid MSG control values: #{e.message}"
    end

    def parse_hmsg_control_line(control_line)
      tokens = control_line.split(" ")
      raise ProtocolError, "malformed HMSG line: #{control_line.inspect}" unless tokens.first == "HMSG"

      case tokens.length
      when 5
        [tokens[1], Integer(tokens[2]), nil, Integer(tokens[3]), Integer(tokens[4])]
      when 6
        [tokens[1], Integer(tokens[2]), tokens[3], Integer(tokens[4]), Integer(tokens[5])]
      else
        raise ProtocolError, "unexpected HMSG control tokens: #{tokens.length}"
      end
    rescue ArgumentError => e
      raise ProtocolError, "invalid HMSG control values: #{e.message}"
    end

    def publish_with_headers(subject, payload, headers, reply: nil)
      header_block = build_header_block(headers)
      command = build_hpub_command(subject, header_block.bytesize, header_block.bytesize + payload.bytesize, reply: reply)
      @logger.debug("C->S #{command}")

      @write_lock.acquire do
        @stream.write("#{command}#{CR_LF}", flush: false)
        @stream.write(header_block, flush: false)
        @stream.write(payload, flush: false)
        @stream.write(CR_LF, flush: true)
      end
      protocol_payload_out(payload)
    end

    def build_header_block(headers)
      lines = [HEADER_LINE]
      headers.each do |key, value|
        header_name = validate_header_name(key)
        Array(value).each do |item|
          lines << "#{header_name}: #{validate_header_value(item)}"
        end
      end

      "#{lines.join(CR_LF)}#{CR_LF}#{CR_LF}".b
    end

    def parse_header_block(block)
      lines = block.split(CR_LF)
      status = lines.shift
      raise ProtocolError, "invalid header block status: #{status.inspect}" unless status&.start_with?(HEADER_LINE)

      lines.each_with_object({}) do |line, headers|
        next if line.empty?

        key, value = line.split(":", 2)
        raise ProtocolError, "malformed header line: #{line.inspect}" unless key && value

        value = value.sub(/\A[ \t]/, "")
        existing = headers[key]
        headers[key] = existing ? Array(existing).push(value) : value
      end
    end

    def validate_header_name(key)
      name = key.to_s
      raise ArgumentError, "header name cannot be empty" if name.empty?
      raise ArgumentError, "invalid header name: #{name.inspect}" if name.match?(/[:\r\n]/)

      name
    end

    def validate_header_value(value)
      string = value.to_s
      raise ArgumentError, "invalid header value: #{string.inspect}" if string.match?(/[\r\n]/)

      string
    end

    def protocol_payload_out(payload)
      return if payload.empty?

      @logger.debug("C->S PAYLOAD #{payload.inspect}")
    end

    def protocol_payload_in(payload)
      return if payload.empty?

      @logger.debug("S->C PAYLOAD #{payload.inspect}")
    end

    def with_temp_subscription(subject, queue: nil, handler: nil)
      sid = subscribe(subject, queue: queue, handler: handler)
      yield
    ensure
      unsubscribe(sid) if sid
    end

    def build_pub_command(subject, size, reply: nil)
      reply ? "PUB #{subject} #{reply} #{size}" : "PUB #{subject} #{size}"
    end

    def build_hpub_command(subject, header_size, total_size, reply: nil)
      reply ? "HPUB #{subject} #{reply} #{header_size} #{total_size}" : "HPUB #{subject} #{header_size} #{total_size}"
    end

    def nkey_connect_fields
      return {} unless nkey_auth?

      nonce = server_info&.dig(:nonce).to_s
      raise ProtocolError, "server nonce is required for nkey auth" if nonce.empty?

      {nkey: nkey_public_key_value, sig: nkey_signature(nonce)}
    end

    def auth_connect_fields
      return {user: @auth_user, pass: @auth_password} if @auth_user && @auth_password
      return {auth_token: @auth_user} if @auth_user

      nkey_connect_fields
    end

    def nkey_auth? = !nkey_seed_value.to_s.empty?

    def nkey_seed_value
      return @nkey_seed if @nkey_seed
      return unless @nkey_seed_file

      @nkey_seed = File.read(@nkey_seed_file).strip
    end

    def nkey_public_key_value
      return @nkey_public_key if @nkey_public_key

      with_nkey_pair { |kp| @nkey_public_key = kp.public_key.dup }
    end

    def nkey_signature(nonce)
      with_nkey_pair do |kp|
        Base64.urlsafe_encode64(kp.sign(nonce)).delete("=")
      end
    end

    def with_nkey_pair
      begin
        require "nkeys"
      rescue LoadError
        raise LoadError, "nkeys gem is required for nkey auth"
      end

      seed = nkey_seed_value.to_s
      raise ArgumentError, "nkey_seed or nkey_seed_file is required for nkey signing" if seed.empty?

      kp = NKEYS.from_seed(seed)
      yield kp
    ensure
      kp&.wipe!
    end

    def normalize_subject_prefix(value)
      prefix = value.to_s.strip.sub(/\.+\z/, "")
      raise ArgumentError, "js_api_prefix cannot be empty" if prefix.empty?

      prefix
    end

    def tls_params
      params = {}
      if @tls_verify
        params[:verify_mode] = OpenSSL::SSL::VERIFY_PEER
        params[:ca_file] = @tls_ca_file if @tls_ca_file
        params[:ca_path] = @tls_ca_path if @tls_ca_path
      else
        params[:verify_mode] = OpenSSL::SSL::VERIFY_NONE
      end

      params
    end

    def tls_hostname_for_ssl(default_host)
      return @tls_hostname if @tls_hostname
      return nil unless @tls_verify

      default_host
    end

    def wrap_tls_socket(socket, host)
      context = OpenSSL::SSL::SSLContext.new
      context.set_params(tls_params)
      ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, context)
      ssl_socket.sync_close = true
      if (hostname = tls_hostname_for_ssl(host))
        ssl_socket.hostname = hostname if ssl_socket.respond_to?(:hostname=)
      end
      ssl_socket.connect
      ssl_socket
    rescue StandardError
      ssl_socket&.close rescue nil
      socket.close rescue nil
      raise
    end

    def presence(value)
      stripped = value.to_s.strip
      stripped.empty? ? nil : stripped
    end

    def safe_close_stream
      @stream&.close
      @stream = nil
    rescue StandardError
      @stream = nil
    end
  end
end
