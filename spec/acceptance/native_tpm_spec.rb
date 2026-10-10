require "spec_helper"
I18n.load_path << File.expand_path("../../locales/en.yml", __dir__)

RSpec.describe VagrantPlugins::QEMU::Driver, "native owned TPM2 lifecycle", :requires_native_qemu do
  def query_tpm(path)
    Timeout.timeout(5) do
      Socket.unix(path) do |peer|
        JSON.parse(peer.gets)
        peer.puts(JSON.generate(execute: "qmp_capabilities"))
        loop do
          response = JSON.parse(peer.gets)
          break if response.key?("return") || response.key?("error")
        end
        peer.puts(JSON.generate(execute: "query-tpm"))
        loop do
          response = JSON.parse(peer.gets)
          return response.fetch("return") if response.key?("return")
          raise response.inspect if response.key?("error")
        end
      end
    end
  end

  def native_options
    config = VagrantPlugins::QEMU::Config.new
    config.arch = "x86_64"
    config.tpm = true
    config.finalize!
    config.instance_variables.to_h { |key| [key.to_s.delete_prefix("@").to_sym, config.instance_variable_get(key)] }.merge(
      qemu_bin: ENV.fetch("QEMU_BINARY"), machine: "q35,accel=kvm", cpu: "host", memory: "512M", smp: "2",
      firmware: ENV.fetch("QEMU_FIRMWARE"), efi_vars: ENV.fetch("QEMU_EFI_VARS"),
      image_path: [], ports: [], net_device: nil, drive_interface: nil)
  end

  it "retains real TPM NV across halt/start, refuses mismatched identities and destroys without an orphan" do
    skip "TPM2 emulator is Linux-only" unless RbConfig::CONFIG["host_os"] =~ /linux/
    with_temp_dir do |dir|
      opts = native_options
      importer = described_class.new(nil, dir.join("data"), dir.join("tmp"))
      id = importer.import(opts).fetch(:id)
      driver = described_class.new(id, dir.join("data"), dir.join("tmp"))
      begin
        driver.start(opts)
        runtime = JSON.parse(driver.tmp_dir.join(id, "runtime.json").read)
        owner = runtime.fetch("tpm")
        expect(query_tpm(runtime.fetch("control").fetch("path")))
          .to include(hash_including("id" => "vmlab_tpm", "model" => "tpm-crb", "options" => hash_including("type" => "emulator")))
        state_dir = Pathname.new(owner.fetch("state_dir"))
        expect(state_dir.stat.mode & 0077).to eq(0)
        expect(File.stat(owner.fetch("control_path")).mode & 0077).to eq(0)
        first_pid = owner.fetch("pid")
        backend = driver.send(:tpm_backend)
        original_record = backend.record_path.read
        corrupted = JSON.parse(original_record).merge("start_ticks" => "0")
        begin
          backend.record_path.write(JSON.generate(corrupted))
          expect { backend.stop }.to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
          expect(File.readlink("/proc/#{first_pid}/exe")).to eq(owner.fetch("executable"))
        ensure
          backend.record_path.write(original_record)
        end
        driver.stop(graceful_timeout: 1)
        expect { File.readlink("/proc/#{first_pid}/exe") }.to raise_error(Errno::ENOENT)
        nv = state_dir.join("tpm2-00.permall")
        retained = nv.binread
        puts "Native TPM halt: PID=#{first_pid} exited; retained NV=#{nv}"
        driver = described_class.new(id, dir.join("data"), dir.join("tmp"))
        # A paused diagnostic CPU prevents guest NV writes during the assertion.
        driver.start(opts.merge(extra_qemu_args: ["-S"]))
        expect(nv.binread).to eq(retained)
        second = JSON.parse(driver.tmp_dir.join(id, "runtime.json").read)
        second_pid = second.fetch("tpm").fetch("pid")
        expect(query_tpm(second.fetch("control").fetch("path")))
          .to include(hash_including("model" => "tpm-crb"))
        allow(driver).to receive(:send_monitor).and_return(nil)
        driver.stop(graceful_timeout: 0)
        expect { File.readlink("/proc/#{second_pid}/exe") }.to raise_error(Errno::ENOENT)
        expect(nv.binread).to eq(retained)
        RSpec::Mocks.space.proxy_for(driver).reset
        driver.delete
        expect(state_dir).not_to exist
        expect(File.exist?(owner.fetch("control_path"))).to eq(false)
        puts "Native TPM forced halt/destroy: PID=#{second_pid} exited; state and local control removed"
      ensure
        RSpec::Mocks.space.proxy_for(driver).reset
        driver.stop(graceful_timeout: 0) if driver.running?
        driver.delete
      end
    end
  end

  it "survives ordinary CLI process exit and is stopped by the next owner" do
    skip "TPM2 emulator is Linux-only" unless RbConfig::CONFIG["host_os"] =~ /linux/
    with_temp_dir do |dir|
      opts = native_options
      id = described_class.new(nil, dir.join("data"), dir.join("tmp")).import(opts).fetch(:id)
      driver = described_class.new(id, dir.join("data"), dir.join("tmp"))
      child = <<~RUBY
        require "vagrant"
        require "vagrant-qemu/errors"
        require "vagrant-qemu/driver"
        root = Pathname.new(ARGV.fetch(1))
        driver = VagrantPlugins::QEMU::Driver.new(ARGV.fetch(0), root.join("data"), root.join("tmp"))
        driver.start(JSON.parse(ARGV.fetch(2), symbolize_names: true))
      RUBY
      begin
        cli_pid = Process.spawn(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", child,
                                id, dir.to_s, JSON.generate(opts), out: dir.join("cli.log").to_s, err: [:child, :out])
        _, status = Process.waitpid2(cli_pid)
        expect(status.success?).to eq(true), dir.join("cli.log").read
        runtime = JSON.parse(driver.tmp_dir.join(id, "runtime.json").read)
        owner = runtime.fetch("tpm")
        expect(File.readlink("/proc/#{owner.fetch("pid")}/exe")).to eq(owner.fetch("executable"))
        expect(query_tpm(runtime.fetch("control").fetch("path"))).to include(hash_including("model" => "tpm-crb"))
        driver.stop(graceful_timeout: 0)
        expect { File.readlink("/proc/#{owner.fetch("pid")}/exe") }.to raise_error(Errno::ENOENT)
        puts "Native TPM CLI-exit: CLI=#{cli_pid} exited normally; TPM=#{owner.fetch("pid")} survived and next owner stopped it"
      ensure
        driver.stop(graceful_timeout: 0) if driver.running?
        driver.delete
      end
    end
  end

  it "leaves no TPM orphan when QEMU rejects the actual launch" do
    skip "TPM2 emulator is Linux-only" unless RbConfig::CONFIG["host_os"] =~ /linux/
    with_temp_dir do |dir|
      opts = native_options
      id = described_class.new(nil, dir.join("data"), dir.join("tmp")).import(opts).fetch(:id)
      driver = described_class.new(id, dir.join("data"), dir.join("tmp"))
      begin
        expect { driver.start(opts.merge(extra_qemu_args: ["--vmlab-invalid-native-option"])) }
          .to raise_error(VagrantPlugins::QEMU::Errors::ExecuteError)
        backend = driver.send(:tpm_backend)
        expect(backend.record_path).not_to exist
        expect(backend.control_path).not_to exist
        live_owners = Dir.glob("/proc/[0-9]*/cmdline").select do |path|
          begin
            File.binread(path).split("\0").include?("dir=#{backend.state_dir},mode=0600")
          rescue Errno::ENOENT, Errno::EACCES
            false
          end
        end
        expect(live_owners).to be_empty
        puts "Native TPM rejected-QEMU cleanup: no process owns #{backend.state_dir}; control and owner record removed"
      ensure
        driver.stop(graceful_timeout: 0) if driver.running?
        driver.delete
      end
    end
  end

  it "recovers a dead backend with a lost socket directory without deleting retained NV" do
    skip "TPM2 emulator is Linux-only" unless RbConfig::CONFIG["host_os"] =~ /linux/
    with_temp_dir do |dir|
      opts = native_options
      id = described_class.new(nil, dir.join("data"), dir.join("tmp")).import(opts).fetch(:id)
      driver = described_class.new(id, dir.join("data"), dir.join("tmp"))
      begin
        driver.start(opts)
        runtime = JSON.parse(driver.tmp_dir.join(id, "runtime.json").read)
        owner = runtime.fetch("tpm")
        query_tpm(runtime.fetch("control").fetch("path"))
        driver.send(:force_kill)
        # This is our unreaped child, so its PID cannot be reused before waitpid.
        Process.kill("TERM", owner.fetch("pid"))
        Process.waitpid(owner.fetch("pid"))
        backend = driver.send(:tpm_backend)
        nv = backend.state_dir.join("tpm2-00.permall")
        retained = nv.binread
        FileUtils.rm_rf(File.dirname(owner.fetch("control_path")))
        driver.stop(graceful_timeout: 0)
        expect(backend.record_path).not_to exist
        expect(nv.binread).to eq(retained)
        driver.delete
        expect(backend.state_dir).not_to exist
        puts "Native TPM lost-socket recovery: dead backend reconciled, NV retained on halt and removed on destroy"
      ensure
        driver.stop(graceful_timeout: 0) if driver.running?
        driver.delete
      end
    end
  end
end
