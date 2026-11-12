module Kamander
  module Ci
    # Each test step's time across runs, like ci-report's "median step times".
    class StepTimes
      Point = Data.define(:run, :seconds)

      Row = Data.define(:name, :points) do
        def median
          sorted = points.map(&:seconds).sort
          (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
        end

        def latest = points.last.seconds

        # remote-ci's own bar for a changed step: 5 s and 10% or more.
        def slow?(seconds)
          change = seconds - median
          change >= 5 && change >= median * 0.1
        end

        def slower? = slow?(latest)
      end

      def initialize(runs)
        @runs = runs.select(&:started_at).sort_by(&:started_at)
      end

      def rows
        points = Hash.new { |hash, name| hash[name] = [] }
        @runs.each do |run|
          run.steps.each do |step|
            next unless step.name.start_with?("Tests:") && step.passed? && step.seconds.to_f.positive?

            points[step.name] << Point.new(run: run, seconds: step.seconds.to_f)
          end
        end
        points.sort.map { |name, list| Row.new(name: name, points: list) }
      end
    end
  end
end
