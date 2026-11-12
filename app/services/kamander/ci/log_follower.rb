module Kamander
  module Ci
    # Tails from the end (-n 0): the page rendered the log so far, and the closing refresh fills any gap.
    class LogFollower
      def self.stream_name(run_id) = "ci_run_#{run_id}"

      def initialize(run:, host:, user:, command_runner: Kamander::Kamal.command_runner)
        @run = run
        @host = host
        @user = user
        @command_runner = command_runner
      end

      def call
        return unless @run.live?

        @command_runner.stream(command: tail_argv, chdir: Rails.root) do |line|
          Turbo::StreamsChannel.broadcast_append_to stream_name, target: "ci_run_log",
            partial: "ci_runs/log_line", locals: { line: line.gsub(RunReader::ANSI_ESCAPE, "") }
        end
        Turbo::StreamsChannel.broadcast_refresh_to stream_name
      end

      private

      def stream_name
        self.class.stream_name(@run.id)
      end

      def tail_argv
        Kamander::Kamal::SshClient.argv(user: @user, host: @host,
          command: "tail -n 0 -f --pid=#{Integer(@run.pid)} #{RunReader::LOGS_DIR}/#{@run.id}.log")
      end
    end
  end
end
