require "spec_helper"
require "open3"
require Vagrant.source_root.join("plugins/guests/windows/cap/public_key").to_s
require "vagrant/util/keypair"

# A bounded local transport fixture runs the UNCHANGED upstream Windows helper
# against real native files/PowerShell ACLs. It is not installed-guest evidence.
class NativeWindowsKeyTransport < VagrantPlugins::CommunicatorWinSSH::Communicator
  def initialize(home, temp)
    @environment = {"USERPROFILE" => home.to_s.tr("/", "\\"), "TEMP" => temp.to_s.tr("/", "\\")}
  end

  def execute(command, shell: "powershell", error_check: true)
    if shell == "cmd"
      stdout, stderr, status = Open3.capture3(@environment, command)
    else
      stdout, stderr, status = Open3.capture3(@environment, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference='Stop'; " + command)
    end
    yield :stdout, stdout if block_given?
    raise "Native fixture command failed: #{stderr}" if error_check && !status.success?
    status.exitstatus
  end

  def download(source, destination)
    FileUtils.cp(source, destination)
  end

  def upload(source, destination)
    FileUtils.cp(source, destination)
  end
end

describe "native Windows bootstrap revocation" do
  before { skip "native Windows files/ACLs required" unless Vagrant::Util::Platform.windows? }

  it "removes every supplied RSA/Ed25519 bootstrap line while preserving an unrelated key and protected ACL" do
    with_temp_dir do |dir|
      home, temp = dir.join("home"), dir.join("transfer")
      FileUtils.mkdir_p(home.join(".ssh"))
      FileUtils.mkdir_p(temp)
      path = home.join(".ssh", "authorized_keys")
      bootstrap = Vagrant.source_root.join("keys", "vagrant.pub").read
      supplied = bootstrap.lines.map(&:strip).reject(&:empty?)
      expect(supplied.map { |line| line.split.first }).to contain_exactly("ssh-rsa", "ssh-ed25519")
      _public, _private, unrelated = Vagrant::Util::Keypair.create(type: :ed25519)
      File.write(path, (supplied + [unrelated.strip]).join("\r\n") + "\r\n")
      expect(path.read.split(/[\r\n]+/)).to eq(supplied + [unrelated.strip])
      comm = NativeWindowsKeyTransport.new(home, temp)
      comm.execute("$acl=Get-Acl '#{path}'; $acl.SetAccessRuleProtection($true,$true); Set-Acl '#{path}' $acl")
      before_acl = ""
      comm.execute("(Get-Acl '#{path}').Sddl") { |_, value| before_acl << value }
      machine = Struct.new(:communicate).new(comm)
      registered = VagrantPlugins::QEMU::Plugin.components.guest_capabilities[:windows].get(:remove_public_key)
      capability = registered || VagrantPlugins::GuestWindows::Cap::PublicKey
      capability.remove_public_key(machine, "\r\n" + bootstrap.chomp + "\r\n\n")
      expect(path.read.split(/[\r\n]+/)).to eq([unrelated.strip])
      after_acl = ""
      comm.execute("(Get-Acl '#{path}').Sddl") { |_, value| after_acl << value }
      expect(after_acl).to eq(before_acl)
      protected_acl = ""
      comm.execute("(Get-Acl '#{path}').AreAccessRulesProtected") { |_, value| protected_acl << value }
      expect(protected_acl.strip).to eq("True")
    end
  end
end
