module Kamander
  module Ci
    # One ci-box run record, read from the box and never stored. `alive` is
    # whether the record's pid is still running this exact record; ci-box
    # leaves a rebooted or kill -9'd run stuck at queued/running forever.
    Run = Data.define(:id, :app, :sha, :branch, :dry_run, :status, :exit_code, :started_at, :finished_at,
                      :host, :pid, :log, :steps, :alive) do
      def self.from_record(record, alive:)
        new(
          id: record["id"],
          app: record["app"],
          sha: record["sha"],
          branch: record["branch"],
          dry_run: record["dry_run"] == true,
          status: record["status"],
          exit_code: record["exit_code"],
          started_at: parse_time(record["started_at"]),
          finished_at: parse_time(record["finished_at"]),
          host: record["host"],
          pid: record["pid"],
          log: record["log"],
          steps: Array(record["steps"]).map { |step| Step.new(name: step["name"], result: step["result"], took: step["took"]) },
          alive: alive
        )
      end

      def self.parse_time(value)
        Time.iso8601(value) if value
      rescue ArgumentError
        nil
      end

      def unfinished?
        status.in?(%w[queued running])
      end

      def live?
        unfinished? && alive
      end

      def lost?
        unfinished? && !alive
      end

      def cancelled?
        status == "error" && exit_code == 143
      end

      def state
        if lost? then "lost"
        elsif cancelled? then "cancelled"
        else status
        end
      end

      def duration(now: Time.current)
        return unless started_at

        ((finished_at || (live? ? now : nil))&.-(started_at))&.round
      end

      def short_sha
        sha.to_s.first(7)
      end
    end
  end
end
