require "rspec/core/rake_task"
require_relative "lib/version"

rspec = RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[rspec]

desc "CI Rspec run with reports"
task :rspec do
  rspec.rspec_opts = "--profile --color -f documentation -f RspecJunitFormatter --out ./results/rspec.xml"
  Rake::Task["spec"].invoke
end

require "erb"

desc "Update readme"
task :readme do
  puts "Update README.erb -> README.md"
  template = File.read("./README.erb")
  renderer = ERB.new(template, trim_mode: "-")
  File.write("./README.md", renderer.result)
end

desc "Build&push new version"
task push: %i[spec readme] do
  puts "Build&push new version"
  system "gem build nats-async.gemspec" or exit 1
  system "gem install ./nats-async-#{NatsAsync::VERSION}.gem" or exit 1
  system "gem push nats-async-#{NatsAsync::VERSION}.gem" or exit 1
  system "gem list -r nats-async" or exit 1
end

desc "Build new version"
task build: %i[spec readme] do
  puts "Build new version"
  system "gem build nats-async.gemspec" or exit 1
end
