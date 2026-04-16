# frozen_string_literal: true

module NatsAsync
  class JetStream
    class Error < RequestError
      attr_reader :code, :err_code, :description

      def initialize(message, code: nil, err_code: nil, description: nil)
        super(message)
        @code = code
        @err_code = err_code
        @description = description
      end
    end

    class NotFound < Error; end
    class ConsumerError < Error; end

    PublishAck = Struct.new(:stream, :seq, :duplicate, keyword_init: true) do
      def duplicate?
        !!duplicate
      end
    end

    class PullSubscription
      def initialize(client:, stream:, consumer:)
        @client = client
        @stream = stream
        @consumer = consumer
        @inbox = "_INBOX.#{rand(1 << 30)}.#{object_id.abs}"
        @sid = @client.subscribe(@inbox) { |message| receive(message) }
      end

      def fetch(batch: 1, timeout: 1)
        @messages = []
        @done = false
        @batch = batch
        @condition = Async::Condition.new

        @client.publish(next_subject, JSON.generate({batch: batch, expires: seconds_to_nanoseconds(timeout)}), reply: @inbox)
        wait_for_messages(timeout)
        @messages
      ensure
        @messages = nil
        @condition = nil
        @batch = nil
        @done = false
      end

      def unsubscribe
        return true unless @sid

        @client.unsubscribe(@sid)
        @sid = nil
        true
      end

      private

      def receive(message)
        return unless @condition

        if status_message?(message)
          @done = true
        else
          @messages << message
        end

        @condition.signal if @done || @messages.size >= @batch
      end

      def wait_for_messages(timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

        until @done || @messages.size >= @batch
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0

          begin
            Async::Task.current.with_timeout(remaining) { @condition.wait }
          rescue Timeout::Error, Async::TimeoutError
            break
          end
        end
      end

      def status_message?(message)
        !message.headers["Status"].to_s.empty?
      end

      def next_subject
        @client.js_api_subject("CONSUMER.MSG.NEXT", @stream, @consumer)
      end

      def seconds_to_nanoseconds(value)
        (value.to_f * 1_000_000_000).to_i
      end
    end

    def initialize(client)
      @client = client
    end

    def stream_info(name)
      api_request("STREAM.INFO", name)
    rescue Error => e
      raise not_found_error(e) if not_found?(e)

      raise
    end

    def available?
      account_info
      true
    rescue Error
      false
    end

    def account_info
      api_request("INFO")
    end

    def stream_exists?(name)
      stream_info(name)
      true
    rescue NotFound
      false
    end

    def add_stream(name, config = nil, **options)
      config = merge_config(config, options).merge(name: name)
      api_request("STREAM.CREATE", name, config)
    end

    def add_stream?(name, config = nil, **options)
      return false if stream_exists?(name)

      add_stream(name, config, **options)
      true
    end

    def delete_stream(name)
      api_request("STREAM.DELETE", name, {})
    end

    def consumer_info(stream, consumer)
      api_request("CONSUMER.INFO", stream, consumer)
    rescue Error => e
      raise not_found_error(e) if not_found?(e)

      raise
    end

    def consumer_exists?(stream, consumer)
      consumer_info(stream, consumer)
      true
    rescue NotFound
      false
    end

    def add_consumer(stream, config = nil, **options)
      config = merge_config(config, options)
      config[:ack_wait] = seconds_to_nanoseconds(config[:ack_wait]) if config[:ack_wait]
      config[:inactive_threshold] = seconds_to_nanoseconds(config[:inactive_threshold]) if config[:inactive_threshold]
      consumer = consumer_name(config)
      subject = consumer ? @client.js_api_subject("CONSUMER.CREATE", stream, consumer) : @client.js_api_subject("CONSUMER.CREATE", stream)
      api_request_subject(subject, {stream_name: stream, config: config})
    rescue Error => e
      raise ConsumerError.new(e.message, code: e.code, err_code: e.err_code, description: e.description)
    end

    def add_consumer?(stream, config = nil, **options)
      config = merge_config(config, options)
      consumer = consumer_name(config)
      return false if consumer && consumer_exists?(stream, consumer)

      add_consumer(stream, config)
      true
    end

    def delete_consumer(stream, consumer)
      api_request("CONSUMER.DELETE", stream, consumer, {})
    end

    def publish(subject, payload = "", headers: nil, timeout: 2)
      message = @client.request(subject, payload, timeout: timeout, headers: headers).wait
      result = JSON.parse(message.data, symbolize_names: true)
      raise_api_error(subject, result[:error]) if result[:error]

      PublishAck.new(stream: result[:stream], seq: result[:seq], duplicate: result[:duplicate])
    rescue JSON::ParserError => e
      raise Error, "JetStream publish returned invalid JSON for #{subject}: #{e.message}"
    end

    def pull_subscribe(subject, stream:, durable: nil, consumer: nil, config: {}, create: true)
      config = merge_config(config, {})
      config[:filter_subject] ||= subject
      config[:ack_policy] ||= "explicit"
      config[:durable_name] ||= durable if durable
      config[:name] ||= consumer if consumer

      consumer_name = consumer_name(config)
      raise ArgumentError, "durable, consumer, config[:name], or config[:durable_name] is required" if consumer_name.to_s.empty?

      add_consumer?(stream, config) if create
      PullSubscription.new(client: @client, stream: stream, consumer: consumer_name)
    end

    private

    def api_request(*tokens)
      payload = tokens.last.is_a?(Hash) ? tokens.pop : {}
      api_request_subject(@client.js_api_subject(*tokens), payload)
    end

    def api_request_subject(subject, payload)
      message = @client.request(subject, payload, timeout: 2).wait
      result = JSON.parse(message.data, symbolize_names: true)
      raise_api_error(subject, result[:error]) if result[:error]

      result
    rescue JSON::ParserError => e
      raise Error, "JetStream API returned invalid JSON for #{subject}: #{e.message}"
    end

    def raise_api_error(subject, error)
      details = error.is_a?(Hash) ? error : {description: error.to_s}
      code = details[:code]
      err_code = details[:err_code]
      description = details[:description] || details[:message] || details.inspect
      klass = not_found_code?(code, description) ? NotFound : Error
      raise klass.new("JetStream API request failed for #{subject}: #{description}", code: code, err_code: err_code, description: description)
    end

    def not_found?(error)
      error.is_a?(NotFound) || not_found_code?(error.code, error.description)
    end

    def not_found_code?(code, description)
      code.to_i == 404 || description.to_s.match?(/not found/i)
    end

    def not_found_error(error)
      NotFound.new(error.message, code: error.code, err_code: error.err_code, description: error.description)
    end

    def merge_config(config, options)
      (config || {}).transform_keys(&:to_sym).merge(options)
    end

    def seconds_to_nanoseconds(value)
      (value.to_f * 1_000_000_000).to_i
    end

    def consumer_name(config)
      config[:name] || config[:durable_name]
    end
  end
end
