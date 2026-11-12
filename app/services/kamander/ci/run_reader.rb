module Kamander
  module Ci
    # Lists ci-box run records over one SSH call. Like SshClient it never
    # raises: an unreachable box comes back as a Listing with an error.
    #
    # The box prints one JSON record per line, a `---` line, then the ids of
    # unfinished records whose pid is still running them. A pid only counts if
    # /proc/<pid>/cmdline is remote-ci's `bash -l -c source …` AND ends with
    # this record's path (remote-ci passes it last), so a pid reused after a
    # reboot can never make a dead run look live.
    class RunReader
      RUNS_DIR = "/data/ci/runs"
      LOGS_DIR = "/data/ci/logs"
      DEFAULT_LIMIT = 50
      LOG_LINES = 2_000
      # Repo names and record ids share this alphabet; nothing else reaches the shell.
      SAFE_NAME = /\A[A-Za-z0-9._-]+\z/
      ANSI_ESCAPE = /\e\[[0-9;]*[A-Za-z]/
      # A sh case pattern for a pid's cmdline that is running the record at %s.
      RUN_CMDLINE = '"bash -l -c source "*" %s "'

      Listing = Data.define(:runs, :error) do
        def success?
          error.nil?
        end
      end

      def initialize(host:, user:, ssh_client: Kamander::Kamal.ssh_client, runs_dir: RUNS_DIR, logs_dir: LOGS_DIR,
        proc_root: "/proc")
        @host = host
        @user = user
        @ssh_client = ssh_client
        @runs_dir = runs_dir
        @logs_dir = logs_dir
        @proc_root = proc_root
      end

      # Records are named <app>-<UTC stamp>-<n>.json and the stamp starts with
      # a digit, so `<app>-[0-9]*` keeps fixxer from matching fixxer-docs.
      def call(app: nil, limit: DEFAULT_LIMIT)
        return refused(app) if app && !app.match?(SAFE_NAME)

        listing = list(app ? "#{app}-[0-9]*.json" : "*.json", limit: Integer(limit))
        app ? listing.with(runs: listing.runs.select { |run| run.app == app }) : listing
      end

      def find(id)
        return refused(id) unless id.match?(SAFE_NAME)

        list("#{id}.json", limit: 1)
      end

      # The tail of a run's log, or nil when the box can't be read.
      def log(id)
        return unless id.match?(SAFE_NAME)

        result = @ssh_client.capture(host: @host, user: @user,
          command: "tail -n #{LOG_LINES} #{@logs_dir.shellescape}/#{id}.log")
        result.stdout.gsub(ANSI_ESCAPE, "") if result.success?
      end

      private

      def refused(name)
        Listing.new(runs: [], error: "not a run or repo name: #{name}")
      end

      def list(glob, limit:)
        result = @ssh_client.capture(host: @host, user: @user, command: script(pattern: "#{@runs_dir.shellescape}/#{glob}", limit: limit))
        return Listing.new(runs: [], error: result.error) unless result.success?

        Listing.new(runs: parse(result.stdout).sort_by { |run| run.started_at || Time.at(0) }.reverse, error: nil)
      rescue JSON::ParserError => e
        Listing.new(runs: [], error: "unreadable run record: #{e.message}")
      end

      def script(pattern:, limit:)
        <<~SH
          files=$(ls -t #{pattern} 2>/dev/null | head -n #{limit})
          if [ -z "$files" ]; then echo ---; exit 0; fi
          jq -c '. + {id: (input_filename | split("/") | last | rtrimstr(".json"))}' $files || exit 1
          echo ---
          jq -r 'select(.status == "queued" or .status == "running") | "\\(.pid) \\(input_filename)"' $files |
          while read -r pid file; do
            cmd=$(tr '\\0' ' ' < #{@proc_root.shellescape}/"$pid"/cmdline 2>/dev/null) || continue
            case "$cmd" in #{format(RUN_CMDLINE, "$file")}) basename "$file" .json ;; esac
          done
        SH
      end

      def parse(stdout)
        records, alive = stdout.split(/^---$/, 2).map { |section| section.lines.map(&:strip).reject(&:empty?) }
        alive_ids = Array(alive).to_set

        records.map do |line|
          record = JSON.parse(line)
          Run.from_record(record, alive: alive_ids.include?(record["id"]))
        end
      end
    end
  end
end
