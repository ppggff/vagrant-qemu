require_relative "helper"

# Regression for #79: `vagrant halt` must actually reap QEMU even when the
# guest OS was already halted from inside (e.g. `sudo systemctl halt`). In that
# state the ACPI `system_powerdown` is a no-op (no live guest to act on it), so
# halt has to escalate to QEMU's `quit` monitor command and, failing that, to
# SIGKILL. A short graceful_timeout keeps the escalation fast.
describe "halt reaps QEMU when the guest is already halted (#79)", :requires_qemu do
  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)

      File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
        Vagrant.configure("2") do |config|
          config.vm.box = "#{test_box}"
          config.vm.box_check_update = false
          config.vm.synced_folder ".", "/vagrant", disabled: true
          config.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.graceful_timeout = 5
          end
        end
      RUBY

      example.run

      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "stops the VM after the guest was halted from inside" do
    vagrant_up(@work_dir)

    # Halt the guest OS from inside; the SSH connection drops as it goes down,
    # so ignore the result. After this, system_powerdown can no longer work.
    vagrant_ssh(@work_dir, command: "sudo systemctl halt", timeout: 30) rescue nil
    sleep 3

    # Without the escalation, QEMU would linger and the VM would still report
    # running; with it, halt reaps the process within ~graceful_timeout.
    result = vagrant_halt(@work_dir, timeout: 60)
    expect(result[:exit_code]).to eq 0

    status = vagrant_status(@work_dir)
    expect(status[:stdout]).to include(",state,stopped")
  end
end
