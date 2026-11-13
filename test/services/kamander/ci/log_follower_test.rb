require "test_helper"

class Kamander::Ci::LogFollowerTest < ActiveSupport::TestCase
  ID = "fixxer-20261112T090000Z-11".freeze
  TAIL = Kamander::Kamal::SshClient.argv(user: "ci", host: "ci-box.test",
    command: "tail -n 0 -f --pid=4242 /data/ci/logs/#{ID}.log")

  test "a live run's new log lines stream to its page, escaped and without colour codes, then the page refreshes" do
    runner = FakeCommandRunner.new(responses: {
      TAIL => { lines: [ "\e[32mRunning 162 tests\e[0m", "<script>alert(1)</script>" ], exit_status: 0 }
    })

    streams = capture_turbo_stream_broadcasts("ci_run_#{ID}") { follow(ci_run(alive: true), runner) }

    assert_equal TAIL, runner.calls.sole.command
    assert_equal %w[append append refresh], streams.map { |stream| stream["action"] }
    assert_equal [ "ci_run_log" ] * 2, streams.first(2).map { |stream| stream["target"] }
    assert_equal "Running 162 tests\n", streams.first.at("template").inner_html
    assert_includes streams.second.at("template").inner_html, "&lt;script&gt;"
  end

  test "a run that is no longer live is not followed" do
    runner = FakeCommandRunner.new

    streams = capture_turbo_stream_broadcasts("ci_run_#{ID}") { follow(ci_run(alive: false), runner) }

    assert_empty runner.calls
    assert_empty streams
  end

  private

    def follow(run, runner)
      Kamander::Ci::LogFollower.new(run: run, host: "ci-box.test", user: "ci", command_runner: runner).call
    end

    def ci_run(alive:)
      Kamander::Ci::Run.from_record(FakeCiBox.record(ID, status: "running").merge(pid: 4242).stringify_keys, alive: alive)
    end
end
