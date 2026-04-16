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
    it "parses status line into Status and Description headers" do
      connection = NatsAsync::Connection.allocate
      header_block = ["NATS/1.0 404 No Messages", "Nats-Subject: inference.jobs", "", ""].join("\r\n")
      headers = connection.__send__(:parse_header_block, header_block)

      expect(headers["Status"]).to eq("404")
      expect(headers["Description"]).to eq("No Messages")
      expect(headers["Nats-Subject"]).to eq("inference.jobs")
    end
  end

  describe NatsAsync::JetStream do
    it "converts consumer duration fields to nanoseconds" do
      client = instance_double("NatsAsync::Client", js_api_subject: "$JS.API.CONSUMER.CREATE.jobs.worker")
      jetstream = NatsAsync::JetStream.new(client)
      captured = nil
      allow(jetstream).to receive(:api_request_subject) do |_subject, payload|
        captured = payload
        {}
      end

      jetstream.add_consumer("jobs", durable_name: "worker", ack_wait: 60, inactive_threshold: 120)

      expect(captured[:stream_name]).to eq("jobs")
      expect(captured[:config]).to include(durable_name: "worker", ack_wait: 60_000_000_000, inactive_threshold: 120_000_000_000)
    end
  end

end
