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
      DEFAULT_LIMIT = 50
      REPO_NAME = /\A[A-Za-z0-9._-]+\z/

      Listing = Data.define(:runs, :error) do
        def success?
          error.nil?
        end
      end

      def initialize(host:, user:, ssh_client: Kamander::Kamal.ssh_client, runs_dir: RUNS_DIR, proc_root: "/proc")
        @host = host
        @user = user
        @ssh_client = ssh_client
        @runs_dir = runs_dir
        @proc_root = proc_root
      end

      def call(app: nil, limit: DEFAULT_LIMIT)
        return Listing.new(runs: [], error: "not a repo name: #{app}") if app && !app.match?(REPO_NAME)

        result = @ssh_client.capture(host: @host, user: @user, command: script(app: app, limit: Integer(limit)))
        return Listing.new(runs: [], error: result.error) unless result.success?

        runs = parse(result.stdout)
        runs = runs.select { |run| run.app == app } if app
        Listing.new(runs: runs.sort_by { |run| run.started_at || Time.at(0) }.reverse, error: nil)
      rescue JSON::ParserError => e
        Listing.new(runs: [], error: "unreadable run record: #{e.message}")
      end

      private

      # Records are named <app>-<UTC stamp>-<n>.json and the stamp starts with
      # a digit, so `<app>-[0-9]*` keeps fixxer from matching fixxer-docs.
      def script(app:, limit:)
        dir = @runs_dir.shellescape
        pattern = app ? "#{dir}/#{app}-[0-9]*.json" : "#{dir}/*.json"

        <<~SH
          files=$(ls -t #{pattern} 2>/dev/null | head -n #{limit})
          if [ -z "$files" ]; then echo ---; exit 0; fi
          jq -c '. + {id: (input_filename | split("/") | last | rtrimstr(".json"))}' $files || exit 1
          echo ---
          jq -r 'select(.status == "queued" or .status == "running") | "\\(.pid) \\(input_filename)"' $files |
          while read -r pid file; do
            cmd=$(tr '\\0' ' ' < #{@proc_root.shellescape}/"$pid"/cmdline 2>/dev/null) || continue
            case "$cmd" in "bash -l -c source "*" $file ") basename "$file" .json ;; esac
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
