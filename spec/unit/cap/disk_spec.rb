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
end
