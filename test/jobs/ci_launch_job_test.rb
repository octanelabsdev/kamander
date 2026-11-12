require "test_helper"

class CiLaunchJobTest < ActiveJob::TestCase
  setup do
    @original_ssh_client = Kamander::Kamal.ssh_client
    @original_command_runner = Kamander::Kamal.command_runner
    @launch = CiLaunch.create!(managed_app: managed_apps(:track_planner), sha: "abc1234def5678", dry_run: true)
  end

  teardown do
    Kamander::Kamal.ssh_client = @original_ssh_client
    Kamander::Kamal.command_runner = @original_command_runner
  end

  test "launching on an unreachable box fails the launch and refreshes its page" do
    Kamander::Kamal.ssh_client = FakeCiBox.new(responses: { "legion" => :unreachable })
    Kamander::Kamal.command_runner = FakeCommandRunner.new

    perform_enqueued_jobs { CiLaunchJob.perform_later(@launch) }

    assert @launch.reload.failed?
    assert_includes @launch.output, "CI box unreachable"
    assert_turbo_stream_broadcasts @launch
  end

  test "a crash inside the job fails the launch instead of leaving it queued forever" do
    Kamander::Kamal.ssh_client = Object.new.tap { |client| def client.capture(**) = raise("boom") }

    CiLaunchJob.perform_now(@launch)

    assert @launch.reload.failed?
    assert_includes @launch.output, "kamander: boom"
  end

  test "launches get their own lane, so log followers holding the ci lane for a whole run can't delay them" do
    assert_equal "ci_launch", CiLaunchJob.new(@launch).queue_name
    assert_includes YAML.load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)
      .dig("default", "workers").flat_map { |worker| worker["queues"] }, "ci_launch"
  end
end
