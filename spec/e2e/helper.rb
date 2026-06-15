require "spec_helper"
require "open3"
require "bundler"

# E2E test box configuration:
#
# TEST_BOX          - Box for basic tests (smoke, forwarded_port).
#                     Any box that boots and has SSH. No cloud-init needed.
#                     Default: "ppggff/centos-7-aarch64-2009-4K"
#
# TEST_BOX_CLOUDINIT - Box for advanced network tests.
#                      Must be an aarch64 box (x86_64 images never boot under
#                      qemu-system-aarch64) and support cloud-init for static
#                      IP configuration.
#                      Default: "perk/ubuntu-2204-arm64"
#
# IMPORTANT: e2e tests run vagrant via Bundler.with_unbundled_env, which means
# they exercise the INSTALLED `vagrant-qemu` plugin, not the in-repo source.
# Before running e2e, build and (re)install the plugin so the installed gem
# matches the source under test:
#
#   bundle exec rake build
#   vagrant plugin install --local ./pkg/vagrant-qemu-<version>.gem
#
# Examples:
#   TEST_BOX=ppggff/centos-7-aarch64-2009-4K TEST_QEMU=1 bundle exec rake spec:e2e
#   TEST_BOX_CLOUDINIT=perk/ubuntu-2204-arm64 TEST_VMNET=1 bundle exec rake spec:e2e

TEST_BOX = ENV.fetch("TEST_BOX", "ppggff/centos-7-aarch64-2009-4K")
TEST_BOX_CLOUDINIT = ENV.fetch("TEST_BOX_CLOUDINIT", "perk/ubuntu-2204-arm64")

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

  def vagrant_ssh(cwd, command:, machine: nil, timeout: 30)
    args = ["ssh"]
    args << machine if machine
    args += ["-c", command]
    run_vagrant_cmd(*args, cwd: cwd, timeout: timeout)
  end

  def vagrant_halt(cwd, timeout: 120)
    run_vagrant_cmd("halt", cwd: cwd, timeout: timeout)
  end

  def vagrant_reload(cwd, timeout: 600)
    run_vagrant_cmd("reload", cwd: cwd, timeout: timeout)
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
    timed_out = false

    # Strip Bundler env so vagrant doesn't load both the installed plugin and
    # the in-repo path-gem simultaneously (which causes capability registration
    # conflicts — disk attach is the visible casualty).
    Bundler.with_unbundled_env do
      # pgroup so a timeout can kill vagrant AND its children. A plain
      # Timeout.timeout around capture3 doesn't stop the child: popen3's
      # ensure joins it, so the suite silently waits out e.g. the box's
      # 30-minute boot_timeout.
      Open3.popen3(env, "vagrant", *args, pgroup: true) do |stdin, out, err, wait_thr|
        stdin.close
        out_reader = Thread.new { out.read }
        err_reader = Thread.new { err.read }

        if wait_thr.join(timeout).nil?
          timed_out = true
          pgid = wait_thr.pid
          Process.kill("TERM", -pgid) rescue nil
          sleep 2
          Process.kill("KILL", -pgid) rescue nil
        end

        status = wait_thr.value
        stdout = out_reader.value
        stderr = err_reader.value
      end
    end

    stderr = "#{stderr}\n[e2e] Timed out after #{timeout}s, killed process group" if timed_out
    { stdout: stdout, stderr: stderr, exit_code: status.exitstatus || -1 }
  end
end

RSpec.configure do |config|
  config.include E2EHelper

  # e2e runs the INSTALLED plugin (see note above) — fail fast when it
  # doesn't match the source tree, instead of silently testing a stale gem.
  config.before(:suite) do
    next unless ENV["TEST_QEMU"] || ENV["TEST_VMNET"]

    require "vagrant-qemu/version"
    expected = VagrantPlugins::QEMU::VERSION
    listing = Bundler.with_unbundled_env { `vagrant plugin list 2>/dev/null` }
    installed = listing[/vagrant-qemu \(([^,)]+)/, 1]

    if installed != expected
      abort <<~MSG
        Installed vagrant-qemu plugin (#{installed || "none"}) does not match the source (#{expected}).
        e2e tests exercise the installed plugin; rebuild and reinstall first:
          bundle exec rake build
          vagrant plugin install ./pkg/vagrant-qemu-#{expected}.gem
      MSG
    end
  end
end
