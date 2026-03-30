require "spec_helper"
require "open3"

# E2E test box configuration:
#
# TEST_BOX          - Box for basic tests (smoke, forwarded_port).
#                     Any box that boots and has SSH. No cloud-init needed.
#                     Default: "ppggff/centos-7-aarch64-2009-4K"
#
# TEST_BOX_CLOUDINIT - Box for advanced network tests.
#                      Must support cloud-init for static IP configuration.
#                      Default: "generic/ubuntu2204"
#
# Examples:
#   TEST_BOX=ppggff/centos-7-aarch64-2009-4K TEST_QEMU=1 bundle exec rake spec:e2e
#   TEST_BOX_CLOUDINIT=generic/ubuntu2204 TEST_VMNET=1 bundle exec rake spec:e2e

TEST_BOX = ENV.fetch("TEST_BOX", "ppggff/centos-7-aarch64-2009-4K")
TEST_BOX_CLOUDINIT = ENV.fetch("TEST_BOX_CLOUDINIT", "generic/ubuntu2204")

module E2EHelper
  def qemu_installed?
    system("which qemu-system-aarch64 > /dev/null 2>&1")
  end

  def vmnet_available?
    RbConfig::CONFIG['host_os'] =~ /darwin/ && Process.uid == 0
  end

  def test_box
    TEST_BOX
  end

  def test_box_cloudinit
    TEST_BOX_CLOUDINIT
  end

  def vagrant_up(cwd, provider: "qemu", timeout: 300)
    run_vagrant_cmd("up", "--provider=#{provider}", cwd: cwd, timeout: timeout)
  end

  def vagrant_ssh(cwd, command:, timeout: 30)
    run_vagrant_cmd("ssh", "-c", command, cwd: cwd, timeout: timeout)
  end

  def vagrant_halt(cwd, timeout: 120)
    run_vagrant_cmd("halt", cwd: cwd, timeout: timeout)
  end

  def vagrant_destroy(cwd, timeout: 60)
    run_vagrant_cmd("destroy", "-f", cwd: cwd, timeout: timeout)
  end

  def vagrant_status(cwd)
    run_vagrant_cmd("status", "--machine-readable", cwd: cwd, timeout: 15)
  end

  private

  def run_vagrant_cmd(*args, cwd:, timeout: 120)
    env = { "VAGRANT_CWD" => cwd.to_s }
    stdout, stderr, status = nil, nil, nil

    Timeout.timeout(timeout) do
      stdout, stderr, status = Open3.capture3(env, "vagrant", *args)
    end

    { stdout: stdout, stderr: stderr, exit_code: status.exitstatus }
  rescue Timeout::Error
    { stdout: "", stderr: "Timed out after #{timeout}s", exit_code: -1 }
  end
end

RSpec.configure do |config|
  config.include E2EHelper
end
