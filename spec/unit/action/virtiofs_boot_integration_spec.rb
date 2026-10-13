require "spec_helper"
require "timeout"
require "vagrant-qemu/synced_folder_virtiofs"

describe "VirtioFS failed-boot recovery" do
  [false, true].each do |running_after_stop|
    it "#{running_after_stop ? 'retains' : 'stops'} the share daemon when QEMU #{running_after_stop ? 'remains running' : 'stops'}" do
      skip "VirtioFS daemons run inside Linux on Windows" if Vagrant::Util::Platform.windows?

      with_temp_dir do |dir|
        ctx = mock_vagrant_env(provider_config_overrides: {
          memory: "256M", control_port: 33333, virtiofsd_bin: RbConfig.ruby
        })
        allow(ctx[:machine]).to receive(:data_dir).and_return(dir)
        allow(ctx[:machine]).to receive(:ui).and_return(ctx[:ui])
        allow(ctx[:ui]).to receive(:error)
        running = false
        allow(ctx[:driver]).to receive(:running?) { running }
        allow(ctx[:driver]).to receive(:start) { running = true }
        expect(ctx[:driver]).to receive(:stop).with(
          control_port: 33333, graceful_timeout: 10, quit_only: true
        ) { running = running_after_stop }

        pid = nil
        prepare = lambda do |_env|
          socket = dir.join("owned.sock").to_s
          pid = Process.spawn(RbConfig.ruby, "-e", "sleep 30", "--", "--socket-path=#{socket}")
          runtime = dir.join("virtiofs")
          FileUtils.mkdir_p(runtime)
          File.write(runtime.join("virtiofs0.pid"), pid.to_s)
          File.write(runtime.join("virtiofs0.sock_path"), socket)
          identity = VagrantPlugins::QEMU::SyncedFolderVirtioFS.new.send(:process_identity, pid)
          File.write(runtime.join("virtiofs0.process.json"), JSON.generate(
            "identity" => identity, "binary" => RbConfig.ruby
          ))
          File.write(runtime.join("mounts.json"), '{}')
          File.write(runtime.join("virtiofs0.log"), 'kept daemon diagnostic')
          ctx[:config].virtiofs_qemu_args = ["-device", "vhost-user-fs-pci"]
        end
        error = Vagrant::Errors::VMBootTimeout.new
        actions = [VagrantPlugins::QEMU::Action::ResetVirtioFSArgs, prepare,
          VagrantPlugins::QEMU::Action::StartInstance, ->(_) { raise error }]

        expect { Vagrant::Action::Warden.new(actions, ctx[:env]).call(ctx[:env]) }.to raise_error(error)
        if running_after_stop
          expect { Process.kill(0, pid) }.not_to raise_error
          expect(ctx[:config].virtiofs_qemu_args).not_to be_empty
        else
          Timeout.timeout(5) { Process.wait(pid) }
          expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
          expect(ctx[:config].virtiofs_qemu_args).to be_empty
        end
        expect(dir.join("virtiofs/mounts.json").exist?).to eq(running_after_stop)
        expect(File.read(dir.join("virtiofs/virtiofs0.log"))).to eq('kept daemon diagnostic')
        expect(ctx[:env]["vagrant.error"]).to equal(error)
      ensure
        if pid
          Process.kill("TERM", pid) rescue Errno::ESRCH
          Process.wait(pid) rescue Errno::ECHILD
        end
      end
    end
  end
end
