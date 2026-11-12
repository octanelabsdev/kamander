require "test_helper"

class Kamander::Ci::StepTimesTest < ActiveSupport::TestCase
  test "each test step lists its passed times oldest first, with the median and the latest" do
    rows = step_times(
      ci_run("c", "2026-11-12T10:00:00Z", { "Tests: Rails" => 44.0, "Tests: System" => 950.0, "Style: Ruby" => 1.0 }),
      ci_run("a", "2026-11-12T08:00:00Z", { "Tests: Rails" => 40.0, "Tests: System" => 30.0 }),
      ci_run("b", "2026-11-12T09:00:00Z", { "Tests: Rails" => 42.0, "Tests: System" => 31.0 })
    )

    assert_equal [ "Tests: Rails", "Tests: System" ], rows.map(&:name)
    system = rows.last
    assert_equal %w[a b c], system.points.map { |point| point.run.id }
    assert_equal [ 30.0, 31.0, 950.0 ], system.points.map(&:seconds)
    assert_equal 31.0, system.median
    assert_equal 950.0, system.latest
    assert system.slower?, "950s against a 31s median is a slowdown"
    assert_not rows.first.slower?, "44s against 42s is under remote-ci's 5s and 10% bar"
  end

  test "runs without timing and failed steps are left out, not counted as zero" do
    rows = step_times(
      ci_run("a", "2026-11-12T08:00:00Z", { "Tests: Rails" => nil }),
      ci_run("b", "2026-11-12T09:00:00Z", { "Tests: Rails" => 40.0 }),
      ci_run("c", "2026-11-12T10:00:00Z", { "Tests: Rails" => 5.0 }, failed: [ "Tests: Rails" ])
    )

    assert_equal [ 40.0 ], rows.sole.points.map(&:seconds)
  end

  test "with no timed runs there are no rows" do
    assert_empty step_times(ci_run("a", "2026-11-12T08:00:00Z", { "Tests: Rails" => nil }))
  end

  private

    def step_times(*runs) = Kamander::Ci::StepTimes.new(runs).rows

    def ci_run(id, started_at, seconds_by_step, failed: [])
      steps = seconds_by_step.map do |name, seconds|
        { "name" => name, "result" => failed.include?(name) ? "failed" : "passed", "took" => "#{seconds}s", "seconds" => seconds }
      end
      Kamander::Ci::Run.from_record({ "id" => id, "app" => "fixxer", "status" => "passed", "started_at" => started_at, "steps" => steps }, alive: false)
    end
end
