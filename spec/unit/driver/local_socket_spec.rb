require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "private POSIX local endpoints" do
  before { skip "POSIX ownership only" if Vagrant::Util::Platform.windows? }

  around do |example|
    next example.run if Vagrant::Util::Platform.windows?
    with_temp_dir do |dir|
      @driver = described_class.new("vq_local", dir.join("x" * 150), dir.join("y" * 150))
      @directory = File.dirname(@driver.send(:local_socket, "monitor"))
      example.run
    ensure
      File.unlink(@directory) if File.symlink?(@directory)
      FileUtils.rm_rf(@directory) if @directory && File.directory?(@directory)
    end
  end

  it "owns short private deterministic endpoints and cleans only after confirmed exit" do
    @driver.send(:prepare_local_sockets)
    expect(File.stat(@directory).mode & 0777).to eq(0700)
    expect(File.stat(@directory).uid).to eq(Process.euid)
    path = @driver.send(:local_socket, "monitor")
    expect(path.bytesize).to be < 108
    server = UNIXServer.new(path)
    server.close
    allow(@driver).to receive(:running?).and_return(true)
    @driver.send(:cleanup_local_sockets)
    expect(File.socket?(path)).to eq(true)
    allow(@driver).to receive(:running?).and_return(false)
    @driver.send(:cleanup_local_sockets)
    expect(File.exist?(@directory)).to eq(false)
  end

  it "rejects symlink or publicly accessible preexisting directories" do
    Dir.mkdir(@directory, 0755)
    expect { @driver.send(:prepare_local_sockets) }.to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
    Dir.rmdir(@directory)
    File.symlink(Dir.tmpdir, @directory)
    expect { @driver.send(:prepare_local_sockets) }.to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
  end
end
