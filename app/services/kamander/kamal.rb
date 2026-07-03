module Kamander
  module Kamal
    # Seam for swapping the SSH client app-wide (system tests, StatusPollJob)
    # without threading ssh_client: through every caller. Defaults to the real
    # client; tests override and restore it around themselves.
    class << self
      attr_writer :ssh_client

      def ssh_client
        @ssh_client ||= SshClient.new
      end
    end
  end
end
