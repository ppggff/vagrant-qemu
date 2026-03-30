require 'rubygems'
require 'bundler/setup'
require 'rspec/core/rake_task'

# Immediately sync all stdout so that tools like buildbot can
# immediately load in the output.
$stdout.sync = true
$stderr.sync = true

# Change to the directory of this file.
Dir.chdir(File.expand_path("../", __FILE__))

# This installs the tasks that help with gem creation and
# publishing.
Bundler::GemHelper.install_tasks

# Test tasks
namespace :spec do
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = "spec/unit/**/*_spec.rb"
    t.rspec_opts = "--order defined"
  end

  RSpec::Core::RakeTask.new(:acceptance) do |t|
    t.pattern = "spec/acceptance/**/*_spec.rb"
    t.rspec_opts = "--order defined"
  end

  RSpec::Core::RakeTask.new(:e2e) do |t|
    t.pattern = "spec/e2e/**/*_spec.rb"
    t.rspec_opts = "--order defined"
  end
end

desc "Run all specs"
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "spec/**/*_spec.rb"
  t.rspec_opts = "--order defined"
end

# build
task :default => :build
