require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "package helpers" do
  let(:vm_id) { "vq_pkgtest" }

  around(:each) do |example|
    with_temp_dir do |dir|
      @data_dir = dir.join("data")
      @tmp_base = dir.join("tmp")
      FileUtils.mkdir_p(@data_dir.join(vm_id))
      FileUtils.mkdir_p(@tmp_base)
      example.run
    end
  end

  subject { described_class.new(vm_id, @data_dir, @tmp_base) }

  describe "#box_disk_paths" do
    it "enumerates box disks by index, matching start/import order (not glob lexical)" do
      id_dir = @data_dir.join(vm_id)
      # Create out of lexical order incl. a two-digit index to catch lexical-sort bugs.
      %w[linked-box.img linked-box-1.img linked-box-2.img].each { |n| FileUtils.touch(id_dir.join(n)) }

      expect(subject.box_disk_paths.map { |p| File.basename(p) })
        .to eq %w[linked-box.img linked-box-1.img linked-box-2.img]
    end

    it "returns a single box.img overlay for a single-disk VM" do
      FileUtils.touch(@data_dir.join(vm_id, "linked-box.img"))
      expect(subject.box_disk_paths.map { |p| File.basename(p) }).to eq %w[linked-box.img]
    end

    it "excludes additional disks and ISOs (only linked-box*.img are box disks)" do
      id_dir = @data_dir.join(vm_id)
      FileUtils.touch(id_dir.join("linked-box.img"))
      FileUtils.touch(id_dir.join("extra-data.qcow2"))
      FileUtils.touch(id_dir.join("vagrant-qemu-network.iso"))

      expect(subject.box_disk_paths.map { |p| File.basename(p) }).to eq %w[linked-box.img]
    end
  end

  describe "#convert_box_disk" do
    it "flattens via qemu-img convert to a fresh qcow2 (never mutates the source)" do
      src = @data_dir.join(vm_id, "linked-box.img")
      dst = @data_dir.join(vm_id, "box.img")
      expect(subject).to receive(:execute).with("qemu-img", "convert", "-O", "qcow2", src.to_s, dst.to_s)
      subject.convert_box_disk(src, dst)
    end
  end
end
