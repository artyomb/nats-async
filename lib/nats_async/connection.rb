# frozen_string_literal: true

require "async/condition"
require "async/semaphore"
require "base64"
require "io/endpoint"
require "io/endpoint/host_endpoint"
require "io/stream"
require "json"
require "openssl"
require "timeout"
require "uri"

require_relative "errors"
require_relative "message"

module NatsAsync
  class Connection
    CR_LF = "\r\n"
    HEADER_LINE = "NATS/1.0"

    attr_reader :received_pings, :received_pongs, :sent_pings, :server_info, :last_error

    def initialize(
      url:,
      logger:,
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
      on_message: nil,
      on_error: nil,
      on_info: nil,
      flush_delay: 0.01,
      flush_max_buffer: 5000
    )
      @url = URI(url)
      @logger = logger
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
      @on_message = on_message || ->(_message) {}
      @on_error = on_error || ->(_error) {}
      @on_info = on_info || ->(_info) {}

      @flush_delay = flush_delay
      @flush_max_buffer = flush_max_buffer

      @received_pings = 0
      @received_pongs = 0
      @sent_pings = 0
      @server_info = nil
      @last_error = nil
      @stream = nil
      @read_task = nil
      @closed = true
      @write_lock = Async::Semaphore.new(1)
      @pong_condition = Async::Condition.new
      @pending_flush_count = 0
      @last_flush_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def start(task:)
      return self if connected?

      connect!
      read_initial_info!
      send_connect!
      @read_task = task.async { read_loop }
      @stale_flush_task = task.async { stale_flush_loop }
      @closed = false
      self
    rescue StandardError
      close
      raise
    end

    def close
      flush_pending if @stream
      @stale_flush_task&.stop
      @read_task&.stop
      safe_close_stream
      @read_task = nil
      @stale_flush_task = nil
      @closed = true
      true
    end

    def connected?
      !@closed && !@stream.nil?
    end

    def ping!(timeout: 2)
      expected_pongs = @received_pongs + 1

      @sent_pings += 1
      write_line("PING")
      await(timeout: timeout, condition: @pong_condition, timeout_message: "timeout waiting for PONG after #{timeout}s", predicate: lambda {
        raise @last_error if @last_error
        @received_pongs >= expected_pongs
      })
    end

    def publish(subject, payload = "", reply: nil, headers: nil)
      payload = payload.to_s
      return publish_with_headers(subject, payload, headers, reply: reply) if headers && !headers.empty?

      command = build_pub_command(subject, payload.bytesize, reply: reply)
      @logger.debug("C->S #{command}")

      @write_lock.acquire do
        stream.write("#{command}#{CR_LF}", flush: false)
        stream.write(payload, flush: false)
        stream.write(CR_LF, flush: false)
        mark_pending_flush
      end

      flush_pending if @pending_flush_count >= @flush_max_buffer
      protocol_payload_out(payload)
    end

    def subscribe(subject, sid:, queue: nil)
      command = queue ? "SUB #{subject} #{queue} #{sid}" : "SUB #{subject} #{sid}"
      write_line(command)
      sid
    end

    def unsubscribe(sid)
      write_line("UNSUB #{sid}") if connected?
      true
    end

    def flush_pending
      return unless @pending_flush_count&.positive?

      @write_lock.acquire do
        stream.write("", flush: true)
        mark_flushed
      end
    end

    def should_flush?
      return false unless @pending_flush_count&.positive?
      return true if @pending_flush_count >= @flush_max_buffer

      now = monotonic_now
      (now - @last_flush_time) >= @flush_delay
    end

    private

    def connect!
      host = @url.host || "127.0.0.1"
      port = @url.port || 4222
      socket = IO::Endpoint.tcp(host, port).connect
      @stream = IO.Stream(socket)

      return unless @tls_enabled

      @server_info = parse_info_line(read_line) unless @tls_handshake_first
      @on_info.call(@server_info) if @server_info
      socket = wrap_tls_socket(socket, host)
      @stream = IO.Stream(socket)
    end

    def read_initial_info!
      return if @server_info

      @server_info = parse_info_line(read_line)
      @on_info.call(@server_info)
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
          @on_info.call(@server_info)
        when /\AHMSG\s+/
          dispatch_hmsg(line)
        when /\AMSG\s+/
          dispatch_msg(line)
        end
      end
    rescue StandardError => e
      @last_error = e
      @closed = true
      safe_close_stream
      @on_error.call(e)
    end

    def stale_flush_loop
      sleep(@flush_delay)

      loop do
        flush_pending if should_flush?
        sleep(@flush_delay)
      end
    end

    def write_line(data)
      @write_lock.acquire do
        stream.write("#{data}#{CR_LF}", flush: true)
        mark_flushed
      end
      @logger.debug("C->S #{data}")
    end

    def mark_pending_flush
      @pending_flush_count += 1
    end

    def mark_flushed
      @pending_flush_count = 0
      @last_flush_time = monotonic_now
    end

    def read_line
      data = stream.read_until(CR_LF, chomp: true)
      raise EOFError, "socket closed" unless data

      @logger.debug("S->C #{data}")
      data
    end

    def stream
      @stream || raise(ConnectionError, "connection is closed")
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

    def parse_info_line(line)
      raise ProtocolError, "expected INFO, got: #{line.inspect}" unless line.start_with?("INFO ")

      JSON.parse(line.delete_prefix("INFO "), symbolize_names: true)
    rescue JSON::ParserError => e
      raise ProtocolError, "invalid INFO payload: #{e.message}"
    end

    def dispatch_msg(control_line)
      subject, sid, reply, size = parse_msg_control_line(control_line)
      payload = stream.read_exactly(size)
      suffix = stream.read_exactly(CR_LF.bytesize)
      raise ProtocolError, "malformed MSG payload ending: #{suffix.inspect}" unless suffix == CR_LF

      dispatch_message(Message.new(subject: subject, sid: sid, reply: reply, data: payload, connector: self))
    rescue StandardError => e
      @logger.error("message dispatch error: #{e.class}: #{e.message}")
    end

    def dispatch_hmsg(control_line)
      subject, sid, reply, header_size, total_size = parse_hmsg_control_line(control_line)
      raise ProtocolError, "HMSG header size exceeds total size" if header_size > total_size

      data = stream.read_exactly(total_size)
      suffix = stream.read_exactly(CR_LF.bytesize)
      raise ProtocolError, "malformed HMSG payload ending: #{suffix.inspect}" unless suffix == CR_LF

      header_block = data.byteslice(0, header_size) || +""
      payload = data.byteslice(header_size, total_size - header_size) || +""
      headers = parse_header_block(header_block)
      dispatch_message(Message.new(subject: subject, sid: sid, reply: reply, data: payload, connector: self, headers: headers))
    rescue StandardError => e
      @logger.error("header message dispatch error: #{e.class}: #{e.message}")
    end

    def dispatch_message(message)
      protocol_payload_in(message.data)
      @on_message.call(message)
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
        stream.write("#{command}#{CR_LF}", flush: false)
        stream.write(header_block, flush: false)
        stream.write(payload, flush: false)
        stream.write(CR_LF, flush: false)
        mark_pending_flush
      end

      flush_pending if @pending_flush_count >= @flush_max_buffer

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

      headers = parse_header_status(status)

      lines.each do |line|
        next if line.empty?

        key, value = line.split(":", 2)
        raise ProtocolError, "malformed header line: #{line.inspect}" unless key && value

        value = value.sub(/\A[ \t]/, "")
        existing = headers[key]
        headers[key] = existing ? Array(existing).push(value) : value
      end

      headers
    end

    def parse_header_status(status)
      headers = {}
      match = status.match(/\ANATS\/1\.0(?:\s+(\d{3}))?(?:\s+(.*))?\z/)
      return headers unless match

      headers["Status"] = match[1] if match[1] && !match[1].empty?
      headers["Description"] = match[2] if match[2] && !match[2].empty?
      headers
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
