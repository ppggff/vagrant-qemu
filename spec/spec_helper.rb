require "pathname"
require "tmpdir"
require "fileutils"
require "yaml"
require "rspec/its"

# Ensure vagrant is loaded
require "vagrant"

# Load the plugin and all its components
require "vagrant-qemu"
require "vagrant-qemu/config"
require "vagrant-qemu/driver"
require "vagrant-qemu/errors"
require "vagrant-qemu/network"
require "vagrant-qemu/action"
require "vagrant-qemu/action/warn_networks"
require "vagrant-qemu/action/destroy"
require "vagrant-qemu/action/start_instance"
require "vagrant-qemu/action/read_state"
require "vagrant-qemu/action/stop_instance"
require "vagrant-qemu/action/prepare_forwarded_port_collision_params"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.order = :defined
  config.filter_run_excluding :requires_qemu unless ENV["TEST_QEMU"]
  config.filter_run_excluding :requires_vmnet unless ENV["TEST_VMNET"]
end

# Helper to create a temporary directory that is cleaned up after the test
def with_temp_dir
  dir = Pathname.new(Dir.mktmpdir("vagrant-qemu-test"))
  yield dir
ensure
  FileUtils.rm_rf(dir)
end

# Helper to create a mock Vagrant environment for action tests
def mock_vagrant_env(provider_config_overrides: {}, networks: [])
  machine = double("machine")
  ui = double("ui", info: nil, warn: nil, output: nil)
  driver = double("driver")
  provider = double("provider", driver: driver)
  vm_config = double("vm_config")

  config_obj = VagrantPlugins::QEMU::Config.new
  provider_config_overrides.each do |k, v|
    config_obj.send("#{k}=", v)
  end
  config_obj.finalize!

  allow(machine).to receive(:provider_config).and_return(config_obj)
  allow(machine).to receive(:provider).and_return(provider)
  allow(machine).to receive(:id).and_return("vq_test123")
  allow(machine).to receive(:id=)
  allow(machine).to receive(:config).and_return(double("config", vm: vm_config))

  allow(vm_config).to receive(:networks).and_return(networks)
  allow(vm_config).to receive(:network)

  env = {
    machine: machine,
    ui: ui,
  }

  { env: env, machine: machine, ui: ui, driver: driver, provider: provider, vm_config: vm_config, config: config_obj }
end
