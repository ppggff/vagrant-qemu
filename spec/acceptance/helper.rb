require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"

module AcceptanceHelper
  # Create a minimal fake qemu binary that writes a PID file and stays running
  def create_fake_qemu(dir)
    bin_dir = dir.join("bin")
    FileUtils.mkdir_p(bin_dir)

    fake = bin_dir.join("qemu-system-aarch64")
    File.write(fake, <<~'SCRIPT')
      #!/bin/bash
      # Parse -pidfile argument
      pidfile=""
      prev=""
      daemonize=false
      for arg in "$@"; do
        if [ "$prev" = "-pidfile" ]; then pidfile="$arg"; fi
        if [ "$arg" = "-daemonize" ]; then daemonize=true; fi
        prev="$arg"
      done

      if [ "$daemonize" = true ] && [ -n "$pidfile" ]; then
        # Fork to background, write PID
        (sleep 3600) &
        child=$!
        echo "$child" > "$pidfile"
      else
        # Foreground mode
        if [ -n "$pidfile" ]; then echo $$ > "$pidfile"; fi
        sleep 3600
      fi
    SCRIPT
    FileUtils.chmod(0755, fake)

    # Also create fake qemu-img
    fake_img = bin_dir.join("qemu-img")
    File.write(fake_img, <<~'SCRIPT')
      #!/bin/bash
      # Fake qemu-img: just touch the output file
      for arg in "$@"; do
        if [[ "$arg" == *.img ]] || [[ "$arg" == *.qcow2 ]]; then
          touch "$arg"
        fi
      done
    SCRIPT
    FileUtils.chmod(0755, fake_img)

    bin_dir
  end

  # Create a minimal Vagrantfile in the given directory
  def create_vagrantfile(dir, content)
    File.write(dir.join("Vagrantfile"), content)
  end

  # Run a vagrant command in the given directory
  def run_vagrant(*args, cwd:, env: {})
    full_env = ENV.to_h.merge(env).merge("VAGRANT_CWD" => cwd.to_s)
    stdout, stderr, status = Open3.capture3(full_env, "vagrant", *args)
    { stdout: stdout, stderr: stderr, exit_code: status.exitstatus }
  end
end

RSpec.configure do |config|
  config.include AcceptanceHelper
end
