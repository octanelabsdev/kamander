module Kamander
  module Kamal
    # Shells out to the system ssh binary via Open3, reusing the machine's own
    # ~/.ssh/config, agent, and known_hosts. Never raises out of #capture — a
    # dead host, a rejected connection, or a hung TCP handshake all come back
    # as a failed Result instead of blowing up the caller.
    class SshClient
      Result = Data.define(:stdout, :success, :error) do
        def success?
          success
        end
      end

      CONNECT_TIMEOUT = 5
      DEFAULT_TIMEOUT = 10

      def capture(host:, user:, command:, timeout: DEFAULT_TIMEOUT)
        run(build_argv(user: user, host: host, command: command), timeout: timeout)
      rescue StandardError => e
        Result.new(stdout: "", success: false, error: e.message)
      end

      private

      def build_argv(user:, host:, command:)
        [
          "ssh",
          "-o", "BatchMode=yes",
          "-o", "ConnectTimeout=#{CONNECT_TIMEOUT}",
          "-o", "StrictHostKeyChecking=accept-new",
          "#{user}@#{host}",
          command
        ]
      end

      # pgroup: true puts ssh in its own process group so a timeout can kill
      # it (and anything it spawned, e.g. a ProxyCommand) in one signal —
      # macOS has no GNU timeout(1) to lean on instead.
      def run(argv, timeout:)
        Open3.popen3(*argv, pgroup: true) do |stdin, stdout, stderr, wait_thread|
          stdin.close
          stdout_reader = Thread.new { stdout.read }
          stderr_reader = Thread.new { stderr.read }

          unless wait_thread.join(timeout)
            kill_process_group(wait_thread.pid)
            wait_thread.join
            # stderr intentionally dropped on timeout — the process is being killed, not
            # finishing normally, so nothing it wrote there is a trustworthy error message.
            next Result.new(stdout: stdout_reader.value.to_s, success: false, error: "timed out after #{timeout}s")
          end

          status = wait_thread.value
          Result.new(
            stdout: stdout_reader.value.to_s,
            success: status.success?,
            error: status.success? ? nil : (stderr_reader.value.to_s.presence || "ssh exited with status #{status.exitstatus}")
          )
        end
      end

      def kill_process_group(pid)
        Process.kill("TERM", -pid)
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
