require "spec_helper"
require "timeout"
require "socket"

describe "open issue regressions" do
  describe "shutdown with a monitor that keeps its connection open (#21)" do
    it "keeps the read side open for a bounded wait when the monitor does not reply" do
      with_temp_dir do |dir|
        driver = VagrantPlugins::QEMU::Driver.new("vm", dir, dir)
        server = TCPServer.new("127.0.0.1", 0)
        received = Queue.new
        release = Queue.new
        peer = nil
        worker = Thread.new do
          peer = server.accept
          received << peer.gets
          release.pop
        end
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Timeout.timeout(2) do
          driver.send(:send_monitor, { control_port: server.addr[1], graceful_timeout: 1 }, "quit")
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        expect(elapsed).to be >= 0.8
        expect(Timeout.timeout(2) { received.pop }).to eq "quit\n"
      ensure
        worker&.kill
        worker&.join
        peer&.close
        server&.close
      end
    end

    it "reaches the kill fallback without waiting for monitor EOF" do
      with_temp_dir do |dir|
        driver = VagrantPlugins::QEMU::Driver.new("vm", dir, dir)
        server = TCPServer.new("127.0.0.1", 0)
        clients = []
        received = Queue.new
        worker = Thread.new do
          loop do
            sock = server.accept
            clients << sock
            received << sock.gets
            # Leave the monitor open, as a stalled QEMU monitor can do.
          end
        end
        allow(driver).to receive(:running?).and_return(true)
        allow(driver).to receive(:force_kill)
        Timeout.timeout(2) { driver.stop(control_port: server.addr[1], graceful_timeout: 0) }
        expect(driver).to have_received(:force_kill)
        commands = Timeout.timeout(2) { [received.pop, received.pop] }
        expect(commands).to eq ["system_powerdown\n", "quit\n"]
      ensure
        worker&.kill
        worker&.join
        clients&.each { |sock| sock.close rescue nil }
        server&.close
      end
    end
  end
end
