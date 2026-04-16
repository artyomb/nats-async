# frozen_string_literal: true

require_relative "errors"

module NatsAsync
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

    attr_reader :subject, :sid, :reply, :data, :headers, :status, :description
    alias header headers

    def initialize(subject:, sid:, reply:, data:, connector:, headers: {}, status: nil, description: nil)
      @subject = subject
      @sid = sid
      @reply = reply
      @data = data
      @headers = Headers.wrap(headers)
      @status = status
      @description = description
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
end
