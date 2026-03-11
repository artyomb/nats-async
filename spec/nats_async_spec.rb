# frozen_string_literal: true

require_relative "spec_helper"

describe NatsAsync do
  # it "exposes a version" do
  #   expect(NatsAsync::VERSION).to eq("0.1.0")
  # end

  it "loads the simple connector" do
    expect(NatsAsync::SimpleConnector).to be_a(Class)
  end
end
