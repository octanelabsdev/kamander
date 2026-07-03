module Kamander
  module Kamal
    # Streams a repo's own bin/kamal (or any local command) line-by-line as it
    # runs, in the repo's own working directory. No timeout — kamal verbs are
    # legitimately long-running and P3 only ever invokes this for a
    # user-initiated operation the operator is actively watching stream.
    class CommandRunner
      def stream(command:, chdir:, env: {}, &block)
        Bundler.with_unbundled_env { run(command, chdir: chdir, env: env, &block) }
      rescue StandardError => e
        block.call("kamander: #{e.message}")
        CommandResult.new(exit_status: nil, success: false)
      end

      private

      # A leading hash argument to Open3 merges onto the inherited environment rather than
      # replacing it — so this layers env: on top of whatever with_unbundled_env left in place
      # (PATH, ssh-agent, the repo's own .kamal/secrets lookups all still work).
      def run(command, chdir:, env:, &block)
        Open3.popen2e(env, *command, chdir: chdir) do |stdin, output, wait_thread|
          stdin.close
          output.each_line { |line| block.call(line.chomp) }

          status = wait_thread.value
          CommandResult.new(exit_status: status.exitstatus, success: status.success? == true)
        end
      end
    end
  end
end
