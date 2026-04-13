# frozen_string_literal: true

module NatsAsync
  class Error < StandardError; end
  class ConnectionError < Error; end
  class AckError < Error; end
  class MsgAlreadyAcked < AckError; end
  class NotAckable < AckError; end
  class RequestError < Error; end
  class ProtocolError < Error; end
end
