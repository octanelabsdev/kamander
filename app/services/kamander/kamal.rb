module Kamander
  module Kamal
    # Seam for swapping the SSH/command clients app-wide (system tests,
    # StatusPollJob, Lifecycle) without threading them through every caller.
    # Default to the real clients; tests override and restore around themselves.
    class << self
      attr_writer :ssh_client, :command_runner

      def ssh_client
        @ssh_client ||= SshClient.new
      end

      def command_runner
        @command_runner ||= CommandRunner.new
      end
    end
  end
end
