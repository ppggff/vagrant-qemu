require "spec_helper"

describe "open issue regressions" do
  describe "primary disk selection (#66)" do
    around do |example|
      with_temp_dir do |dir|
        @driver = VagrantPlugins::QEMU::Driver.new("vm", dir.join("data"), dir.join("tmp"))
        FileUtils.mkdir_p(@driver.disk_dir)
        FileUtils.touch(@driver.disk_dir.join("linked-box.img"))
        example.run
      end
    end

    let(:ui) { double("ui", detail: nil, warn: nil) }
    let(:machine) { double("machine", ui: ui, provider: double("provider", driver: @driver)) }
    let(:disk) do
      double("disk", type: :disk, name: "root", disk_ext: "qcow2", size: 107374182400,
        id: "root-id", primary: true, provider_config: nil)
    end

    before do
      I18n.backend.load_translations(VagrantPlugins::QEMU.source_root.join("locales/en.yml"))
      allow(@driver).to receive(:execute).and_return('{"virtual-size":68719476736}')
    end

    it "grows the existing boot overlay instead of attaching a blank disk" do
      path = @driver.disk_dir.join("linked-box.img").to_s
      allow(@driver).to receive(:execute).with("qemu-img", "resize", path, "107374182400") do
        expect(ui).to have_received(:detail).with(
          "Growing primary disk 'root' from 64 GiB to 100 GiB.\n" \
          "Grow the guest partition and filesystem separately if needed."
        )
      end
      metadata = VagrantPlugins::QEMU::Cap::Disk.configure_disks(machine, [disk])
      expect(@driver).to have_received(:execute).with("qemu-img", "resize", path, "107374182400")
      expect(metadata[:disk].first[:Path]).to eq path
      expect(@driver.attached_drives[:disk]).to be_empty
      expect(ui).not_to have_received(:warn)
      expect(@driver).not_to have_received(:execute).with("qemu-img", "create", any_args)
    end

    it "warns that a blank disk left by an older primary declaration is no longer attached" do
      allow(@driver).to receive(:execute).and_return('{"virtual-size":107374182400}')
      legacy = @driver.disk_dir.join("root.qcow2")
      FileUtils.touch(legacy)
      VagrantPlugins::QEMU::Cap::Disk.configure_disks(machine, [disk])
      expect(ui).to have_received(:warn).with(/#{Regexp.escape(legacy.to_s)}.*no longer attached/m)
      expect(@driver.attached_drives[:disk]).to be_empty
      expect(legacy).to be_file
    end

    it "does not warn about an older primary disk when none exists" do
      allow(@driver).to receive(:execute).and_return('{"virtual-size":107374182400}')
      VagrantPlugins::QEMU::Cap::Disk.configure_disks(machine, [disk])
      expect(ui).not_to have_received(:warn)
    end

    it "does not resize a primary disk again when it is already large enough" do
      allow(@driver).to receive(:execute).and_return('{"virtual-size":107374182400}')
      VagrantPlugins::QEMU::Cap::Disk.configure_disks(machine, [disk])
      expect(@driver).not_to have_received(:execute).with("qemu-img", "resize", any_args)
      expect(@driver.attached_drives[:disk]).to be_empty
      expect(ui).not_to have_received(:detail)
      expect(ui).not_to have_received(:warn)
    end

    it "never shrinks the boot disk to a smaller requested size" do
      allow(disk).to receive(:size).and_return(1024)
      VagrantPlugins::QEMU::Cap::Disk.configure_disks(machine, [disk])
      expect(@driver).not_to have_received(:execute).with("qemu-img", "resize", any_args)
      expect(@driver).not_to have_received(:execute).with("qemu-img", "create", any_args)
      expect(ui).to have_received(:warn).with(
        "Cannot shrink primary disk 'root' from 64 GiB to 1 KiB.\n" \
        "The disk has been kept at its existing size."
      )
      expect(ui).not_to have_received(:detail)
    end

    it "displays fractional GiB while passing the exact byte count to qemu-img" do
      allow(disk).to receive(:size).and_return(69_256_347_648)
      VagrantPlugins::QEMU::Cap::Disk.configure_disks(machine, [disk])
      expect(ui).to have_received(:detail).with(
        "Growing primary disk 'root' from 64 GiB to 64.5 GiB.\n" \
        "Grow the guest partition and filesystem separately if needed."
      )
      expect(@driver).to have_received(:execute).with("qemu-img", "resize",
        @driver.disk_dir.join("linked-box.img").to_s, "69256347648")
    end
  end


end
