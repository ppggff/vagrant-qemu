require "spec_helper"

describe VagrantPlugins::QEMU::Cap::Disk, ".configure_disks" do
  let(:vm_id) { "vq_testid123" }

  around(:each) do |example|
    with_temp_dir do |dir|
      @data_dir = dir.join("data")
      @tmp_base = dir.join("tmp")
      FileUtils.mkdir_p(@data_dir)
      FileUtils.mkdir_p(@tmp_base)
      FileUtils.mkdir_p(@data_dir.join(vm_id))
      example.run
    end
  end

  # A real Driver (not a double) -- attached_drives accumulation is the exact
  # mechanism under test, so it must be the production object.
  let(:driver) { VagrantPlugins::QEMU::Driver.new(vm_id, @data_dir, @tmp_base) }

  let(:machine) do
    provider = double("provider", driver: driver)
    double("machine", provider: provider)
  end

  let(:disk) do
    double("disk",
      type: :disk, name: "disk1", disk_ext: "qcow2", size: "10G",
      id: "disk1-uuid", primary: false, provider_config: nil)
  end

  before do
    # Avoid actually shelling out to qemu-img.
    allow(driver).to receive(:execute)
  end

  it "reflects one entry per disk after a single configure_disks call" do
    described_class.configure_disks(machine, [disk])

    expect(driver.attached_drives[:disk].length).to eq(1)
  end

  it "does not duplicate a disk across a second configure_disks call on the same driver (reload)" do
    described_class.configure_disks(machine, [disk])
    # action_start (and its Disk middleware) re-runs on the same Driver
    # instance during a same-process reload (action_halt -> action_start).
    described_class.configure_disks(machine, [disk])

    expect(driver.attached_drives[:disk].length).to eq(1)
  end

  it "does not accumulate across repeated reloads" do
    3.times { described_class.configure_disks(machine, [disk]) }

    expect(driver.attached_drives[:disk].length).to eq(1)
  end

  it "clears a stale disk once it is removed from the Vagrantfile" do
    described_class.configure_disks(machine, [disk])
    expect(driver.attached_drives[:disk].length).to eq(1)

    described_class.configure_disks(machine, [])

    expect(driver.attached_drives[:disk]).to be_empty
  end

  describe "disk file idempotency (reload must not wipe existing disk data)" do
    let(:disk_path) { @data_dir.join(vm_id).join("disk1.qcow2") }

    it "does not recreate the qcow2 file when it already exists" do
      FileUtils.touch(disk_path)

      expect(driver).not_to receive(:execute)
        .with("qemu-img", "create", "-f", "qcow2", disk_path.to_s, "10G")

      described_class.configure_disks(machine, [disk])
    end

    it "does not recreate on a second configure_disks call (reload)" do
      # Simulate the real qemu-img side effect (the outer stub is a no-op),
      # so the second call's existence check reflects what actually happens.
      allow(driver).to receive(:execute) do |*args|
        FileUtils.touch(disk_path) if args[0, 2] == ["qemu-img", "create"]
      end

      described_class.configure_disks(machine, [disk])
      expect(File.exist?(disk_path)).to be true

      expect(driver).not_to receive(:execute)
        .with("qemu-img", "create", "-f", "qcow2", disk_path.to_s, "10G")

      described_class.configure_disks(machine, [disk])
    end

    it "creates the qcow2 file when it does not exist yet" do
      expect(File.exist?(disk_path)).to be false

      expect(driver).to receive(:execute)
        .with("qemu-img", "create", "-f", "qcow2", disk_path.to_s, "10G")

      described_class.configure_disks(machine, [disk])
    end
  end
end
