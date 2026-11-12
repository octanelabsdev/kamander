module Kamander
  module Ci
    # Sends TERM to a run's pid only if, in that same command, its cmdline is
    # still that run: a pid reused after a reboot is never signalled.
    class Canceller
      SENT = "kamander: cancel sent"

      Result = Data.define(:success, :message) do
        def success? = success
      end

      def initialize(host:, user:, ssh_client: Kamander::Kamal.ssh_client, runs_dir: RunReader::RUNS_DIR, proc_root: "/proc")
        @host = host
        @user = user
        @ssh_client = ssh_client
        @runs_dir = runs_dir
        @proc_root = proc_root
      end

      def call(run)
        result = @ssh_client.capture(host: @host, user: @user, command: script(run))
        return Result.new(success: false, message: "CI box unreachable: #{result.error}") if result.stdout.empty? && !result.success?

        Result.new(success: result.stdout.include?(SENT), message: result.stdout.strip)
      end

      private

        def script(run)
          pid = Integer(run.pid)
          record = "#{@runs_dir}/#{run.id}.json".shellescape
          <<~SH
            cmd=$(tr '\\0' ' ' < #{@proc_root.shellescape}/#{pid}/cmdline 2>/dev/null) || { echo "kamander: #{run.id} is no longer running"; exit 3; }
            case "$cmd" in
              #{format(RunReader::RUN_CMDLINE, record)}) kill -TERM #{pid} && echo "#{SENT}" ;;
              *) echo "kamander: pid #{pid} is not this run any more"; exit 3 ;;
            esac
          SH
        end
    end
  end
end
