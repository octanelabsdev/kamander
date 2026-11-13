module Kamander
  module Ci
    # ci-box leaves a rebooted or kill -9'd run at queued/running forever, so `alive` decides live vs lost.
    Run = Data.define(:id, :app, :sha, :branch, :dry_run, :status, :exit_code, :started_at, :finished_at,
                      :host, :pid, :log, :steps, :slowest, :alive) do
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
          steps: Array(record["steps"]).map { |step| Step.new(name: step["name"], result: step["result"], took: step["took"], seconds: step["seconds"]) },
          slowest: record.key?("slowest") ? slow_tests(record["slowest"]) : nil,
          alive: alive
        )
      end

      # Records before ci-box #4 have no "slowest"; nil keeps that unknown, apart from {} (no --profile).
      def self.slow_tests(by_step)
        by_step.to_h.flat_map do |step, tests|
          tests.map { |test| SlowTest.new(step: step, test: test["test"], seconds: test["seconds"], file: test["file"], line: test["line"]) }
        end.sort_by { |test| -test.seconds.to_f }
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
        ended_at = finished_at || (now if live?)
        (ended_at - started_at).round if started_at && ended_at
      end

      def short_sha
        sha.to_s.first(7)
      end

      # The "Signoff: …" step stamps gh signoff; dry runs skip it.
      def signed_off?
        steps.any? { |step| step.name.start_with?("Signoff") && step.passed? }
      end

      def failed_step
        steps.find { |step| !step.passed? }
      end
    end
  end
end
