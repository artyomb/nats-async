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
end
