# frozen_string_literal: true

require_relative "spec_helper"

describe NatsAsync do
  # it "exposes a version" do
  #   expect(NatsAsync::VERSION).to eq("0.1.0")
  # end

  it "loads the client" do
    expect(NatsAsync::Client).to be_a(Class)
    expect(NatsAsync::Connection).to be_a(Class)
    expect(NatsAsync::Message).to be_a(Class)
    expect(NatsAsync::Error).to be < StandardError
  end

  describe NatsAsync::Connection do
    it "parses the header status line separately from headers" do
      connection = NatsAsync::Connection.allocate
      header_block = ["NATS/1.0 404 No Messages", "Nats-Subject: inference.jobs", "", ""].join("\r\n")
      status, description, headers = connection.__send__(:parse_header_block, header_block)

      expect(status).to eq("404")
      expect(description).to eq("No Messages")
      expect(headers["Nats-Subject"]).to eq("inference.jobs")
      expect(headers["Status"]).to be_nil
    end
  end

  describe NatsAsync::JetStream do
    it "passes consumer config through unchanged" do
      client = instance_double("NatsAsync::Client", js_api_subject: "$JS.API.CONSUMER.CREATE.jobs.worker")
      jetstream = NatsAsync::JetStream.new(client)
      captured = nil
      allow(jetstream).to receive(:api_request_subject) do |_subject, payload|
        captured = payload
        {}
      end

      jetstream.add_consumer("jobs", durable_name: "worker", ack_wait: 60, inactive_threshold: 120)

      expect(captured[:stream_name]).to eq("jobs")
      expect(captured[:config]).to include(durable_name: "worker", ack_wait: 60, inactive_threshold: 120)
    end

    it "raises on unexpected pull status replies" do
      handler = nil
      client = instance_double(
        NatsAsync::Client,
        subscribe: 1,
        js_api_subject: "$JS.API.CONSUMER.MSG.NEXT.jobs.worker"
      )
      allow(client).to receive(:subscribe) do |_subject, &block|
        handler = block
        1
      end
      allow(client).to receive(:publish) do
        handler.call(
          NatsAsync::Message.new(
            subject: "_INBOX.test",
            sid: 1,
            reply: nil,
            data: "",
            connector: client,
            status: "409",
            description: "Consumer Deleted"
          )
        )
      end

      subscription = NatsAsync::JetStream::PullSubscription.new(client: client, stream: "jobs", consumer: "worker")
      allow(subscription).to receive(:wait_for_messages)

      expect {
        subscription.fetch(batch: 1, timeout: 0.1)
      }.to raise_error(NatsAsync::JetStream::Error, /unexpected JetStream pull status 409: Consumer Deleted/)
    end
  end
end
