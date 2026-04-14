# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/NoExpectationExample
# rubocop:disable RSpec/DescribeClass

require_relative "spec_helper"

require "open3"

RSpec.describe "example scripts" do
  def run_example(example_path, env)
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", example_path, chdir: project_path)
    return if status.success?

    raise <<~MSG
      example failed: #{example_path}
      status: #{status.exitstatus}
      stdout:
      #{stdout}
      stderr:
      #{stderr}
    MSG
  end

  it "runs the bundled examples against the local nats-server", :nats_server do
    run_example("examples/core_lifecycle.rb", {"NATS_URL" => nats_url})
    run_example("examples/queue_group.rb", {"NATS_URL" => nats_url})
    run_example("examples/request_reply.rb", {"NATS_URL" => nats_url})
    run_example("examples/headers_and_binary.rb", {"NATS_URL" => nats_url})
    run_example("examples/jetstream_management.rb", {"NATS_URL" => nats_url})
    run_example("examples/jetstream_publish.rb", {"NATS_URL" => nats_url})
    run_example("examples/backend_detection.rb", {"NATS_URL" => nats_url})
    run_example("examples/jetstream_pull_consumer.rb", {"NATS_URL" => nats_url})
    run_example(
      "examples/jetstream_roundtrip.rb",
      {
        "NATS_URL" => nats_url,
        "JS_STREAM" => "spec_stream",
        "JS_SUBJECT" => "spec.subject",
        "JS_CONSUMER" => "spec_consumer",
        "JS_PAYLOAD" => "spec payload"
      }
    )
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/NoExpectationExample
# rubocop:enable RSpec/DescribeClass
