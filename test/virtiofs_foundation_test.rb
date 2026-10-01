require "minitest/autorun"
require "fileutils"
require "json"
require "ostruct"
require "pathname"
require "securerandom"
require "tmpdir"

# Exercise provider command construction without requiring a VM or Vagrant.
module Vagrant
  def self.plugin(_version, _type = nil)
    Object
  end
end

module Log4r
  class Logger
    def initialize(*); end
  end
end

$LOADED_FEATURES << "vagrant.rb"
$LOADED_FEATURES << "log4r.rb"

require_relative "../lib/vagrant-qemu/synced_folder_virtiofs"
require_relative "../lib/vagrant-qemu/action/mount_virtiofs"

class VirtiofsFoundationTest < Minitest::Test
  Machine = Struct.new(:provider_name, :provider_config, :data_dir, :id, :ui, :communicate, :config)

  class UI
    attr_reader :messages

    def initialize
      @messages = []
    end

    def info(message)
      @messages << message
    end

    def error(message)
      @messages << message
    end
  end

  class Communicator
    attr_reader :commands

    def initialize
      @commands = []
    end

    def sudo(command)
      @commands << command
    end
  end

  def setup
    @dir = Dir.mktmpdir("vagrant-qemu-test-")
    @folder = File.join(@dir, "host share")
    FileUtils.mkdir_p(@folder)
    @machine = Machine.new(
      :qemu,
      OpenStruct.new(
        virtiofsd_bin: nil,
        memory: "256M",
        virtiofs_guest_uid: 1000,
        virtiofs_guest_gid: 1000,
        extra_virtiofsd_args: [],
        virtiofs_qemu_args: []
      ),
      Pathname.new(File.join(@dir, "machine")),
      SecureRandom.hex(8),
      UI.new,
      Communicator.new,
      nil
    )
  end

  def teardown
    socket_path_file = @machine.data_dir.join("virtiofs", "virtiofs0.sock_path")
    if socket_path_file.file?
      args_file = "#{File.read(socket_path_file).strip}.args.json"
      File.delete(args_file) if File.exist?(args_file)
    end
    VagrantPlugins::QEMU::SyncedFolderVirtioFS.new.cleanup(@machine, {})
    FileUtils.remove_entry(@dir) if File.exist?(@dir)
  end

  def test_daemon_arguments_and_qemu_devices
    configure_fake_daemon
    @machine.provider_config.extra_virtiofsd_args = ["--cache=always"]

    VagrantPlugins::QEMU::SyncedFolderVirtioFS.new.prepare(@machine, folders, {})

    args = daemon_args
    assert_includes args, "--shared-dir=#{@folder}"
    assert_includes args, "--sandbox=none"
    assert_includes args, "--inode-file-handles=never"
    assert_includes args, "--translate-uid"
    assert_includes args, "--translate-gid"
    assert_includes args, "--cache=always"

    qemu_args = @machine.provider_config.virtiofs_qemu_args
    assert_includes qemu_args, "memory-backend-file,id=mem,size=256M,mem-path=#{File.join(Dir.tmpdir, "vagrant-qemu-#{@machine.id}-mem")},share=on"
    assert_includes qemu_args, "vhost-user-fs-pci,chardev=char_virtiofs0,tag=virtiofs0"
  end

  def test_prepare_replaces_qemu_arguments_on_reload
    configure_fake_daemon
    adapter = VagrantPlugins::QEMU::SyncedFolderVirtioFS.new

    2.times { adapter.prepare(@machine, folders, {}) }

    args = @machine.provider_config.virtiofs_qemu_args
    assert_equal 1, args.count { |arg| arg.start_with?("memory-backend-file,id=mem,") }
    assert_equal 1, args.count("vhost-user-fs-pci,chardev=char_virtiofs0,tag=virtiofs0")
  end

  def test_mount_quotes_guest_path
    @machine.config = OpenStruct.new(
      vm: OpenStruct.new(
        synced_folders: {
          "share" => { type: "virtiofs", guestpath: "/mnt/a shared folder" }
        }
      )
    )
    called = false

    VagrantPlugins::QEMU::Action::MountVirtioFS.new(->(_env) { called = true }, {}).call(machine: @machine)

    assert_equal [
      "mkdir -p /mnt/a\\ shared\\ folder",
      "mount -t virtiofs virtiofs0 /mnt/a\\ shared\\ folder"
    ], @machine.communicate.commands
    assert called
  end

  private

  def folders
    { "share" => { hostpath: @folder, guestpath: "/vagrant" } }
  end

  def configure_fake_daemon
    daemon_path = File.join(@dir, "virtiofsd")
    File.write(daemon_path, <<~RUBY)
      #!/usr/bin/env ruby
      require "json"
      require "socket"
      if ARGV.include?("--help")
        puts "--translate-uid --translate-gid"
        exit
      end
      socket = ARGV.find { |arg| arg.start_with?("--socket-path=") }.split("=", 2).last
      File.write(socket + ".args.json", JSON.generate(ARGV))
      server = UNIXServer.new(socket)
      sleep 60
    RUBY
    FileUtils.chmod(0755, daemon_path)
    @machine.provider_config.virtiofsd_bin = daemon_path
  end

  def daemon_args
    socket_path_file = @machine.data_dir.join("virtiofs", "virtiofs0.sock_path")
    socket_path = File.read(socket_path_file).strip
    JSON.parse(File.read("#{socket_path}.args.json"))
  end
end
