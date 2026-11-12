require "test_helper"

class CiFollowJobTest < ActiveJob::TestCase
  ID = "fixxer-20261112T090000Z-11".freeze
  TAIL = Kamander::Kamal::SshClient.argv(user: "ci", host: "legion",
    command: "tail -n 0 -f --pid=4242 /data/ci/logs/#{ID}.log")

  setup do
    @original_ssh_client = Kamander::Kamal.ssh_client
    @original_command_runner = Kamander::Kamal.command_runner
  end

  teardown do
    Kamander::Kamal.ssh_client = @original_ssh_client
    Kamander::Kamal.command_runner = @original_command_runner
  end

  test "following a live run streams its log from the CI box as the configured CI user" do
    serve live: true
    runner = Kamander::Kamal.command_runner = FakeCommandRunner.new(responses: { TAIL => { lines: [ "Running 162 tests" ], exit_status: 0 } })

    streams = capture_turbo_stream_broadcasts("ci_run_#{ID}") { CiFollowJob.perform_now(ID) }

    assert_equal TAIL, runner.calls.sole.command
    assert_equal %w[append refresh], streams.map { |stream| stream["action"] }
  end

  test "a run that finished before the job started is left alone" do
    serve live: false
    runner = Kamander::Kamal.command_runner = FakeCommandRunner.new

    CiFollowJob.perform_now(ID)

    assert_empty runner.calls
  end

  test "follows run on the ci lane, one follower per run" do
    assert_equal "ci", CiFollowJob.new(ID).queue_name
    assert_equal :discard, CiFollowJob.concurrency_on_conflict
    assert_equal ID, CiFollowJob.new(ID).concurrency_key.split("/").last
  end

  private

    def serve(live:)
      Kamander::Kamal.ssh_client = FakeCiBox.serving(
        FakeCiBox.record(ID, status: "running").merge(pid: 4242), live: live ? [ ID ] : []
      )
    end
end
