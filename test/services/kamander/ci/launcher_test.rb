require "test_helper"

class Kamander::Ci::LauncherTest < ActiveSupport::TestCase
  NEW_RUN = "fixxer-20261112T100000Z-12".freeze

  setup do
    @repo = Dir.mktmpdir
    git "init", "-q"
    git "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "first"
    @head = git("rev-parse", "HEAD").strip
    @app = managed_apps(:track_planner)
    @app.update!(repo_path: @repo, ci_name: "fixxer")
    @box = FakeCiBox.serving(FakeCiBox.record("fixxer-20261112T090000Z-11", sha: @head))
  end

  teardown { FileUtils.remove_entry(@repo) }

  test "Evan's dry run starts remote-ci --dry-run in the app's repo and the launch points at the run it made" do
    runner = FakeCommandRunner.new(responses: { %w[remote-ci --dry-run] => {
      lines: [ "remote-ci: fixxer @ #{@head.first(7)} (main) on ci@legion [dry run, no signoff]" ],
      on_spawn: -> { @box.records << FakeCiBox.record(NEW_RUN, sha: @head, status: "queued", dry_run: true) }
    } })

    launch = launch!(dry_run: true, runner: runner)

    call = runner.calls.sole
    assert_equal @repo, call.chdir
    assert_equal({ "REMOTE_CI_HOST" => "ci@legion" }, call.env)
    assert launch.started?, launch.output
    assert_equal NEW_RUN, launch.run_id
    assert_includes launch.output, "[dry run, no signoff]"
    assert runner.spawned.sole.stopped, "remote-ci should stop following once the box has the run"
  end

  test "a real run of the same commit started elsewhere isn't mistaken for Evan's dry run" do
    runner = FakeCommandRunner.new(responses: { %w[remote-ci --dry-run] => {
      exit_status: nil,
      on_spawn: -> { @box.records << FakeCiBox.record(NEW_RUN, sha: @head, status: "queued", dry_run: false) }
    } })

    launch = launch!(dry_run: true, runner: runner)

    assert launch.failed?
    assert_nil launch.run_id
  end

  test "a real run is plain remote-ci, which stamps signoff when green" do
    runner = FakeCommandRunner.new(responses: { %w[remote-ci] => {
      on_spawn: -> { @box.records << FakeCiBox.record(NEW_RUN, sha: @head, status: "queued") }
    } })

    assert launch!(dry_run: false, runner: runner).started?
    assert_equal %w[remote-ci], runner.calls.sole.command
  end

  test "remote-ci refuses a dirty tree and Evan sees its own words, not a guess" do
    runner = FakeCommandRunner.new(responses: { %w[remote-ci] => {
      lines: [ "remote-ci: working tree has uncommitted changes; commit and push, or use --dry-run" ], exit_status: 1
    } })

    launch = launch!(dry_run: false, runner: runner)

    assert launch.failed?
    assert_nil launch.run_id
    assert_includes launch.output, "working tree has uncommitted changes"
  end

  test "if HEAD moved after Evan confirmed, nothing runs: the sha he saw is the one that would be signed" do
    runner = FakeCommandRunner.new

    launch = launch!(dry_run: false, runner: runner, sha: "0" * 40)

    assert launch.failed?
    assert_empty runner.calls
    assert_includes launch.output, "HEAD is now #{@head.first(7)}"
  end

  test "with the CI box unreachable nothing runs" do
    @box = FakeCiBox.new(responses: { "legion" => :unreachable })
    runner = FakeCommandRunner.new

    launch = launch!(dry_run: true, runner: runner)

    assert launch.failed?
    assert_empty runner.calls
    assert_includes launch.output, "CI box unreachable"
  end

  test "remote-ci that never makes a record is stopped and the launch says to check the CI page" do
    runner = FakeCommandRunner.new(responses: { %w[remote-ci --dry-run] => { exit_status: nil } })

    launch = launch!(dry_run: true, runner: runner)

    assert launch.failed?
    assert runner.spawned.sole.stopped
    assert_includes launch.output, "no run record on the box"
  end

  test "remote-ci missing from PATH fails the launch with the reason" do
    runner = FakeCommandRunner.new(responses: { %w[remote-ci --dry-run] => { raise: Errno::ENOENT.new("remote-ci") } })

    launch = launch!(dry_run: true, runner: runner)

    assert launch.failed?
    assert_includes launch.output, "No such file or directory"
  end

  private

    def launch!(dry_run:, runner:, sha: @head)
      launch = CiLaunch.create!(managed_app: @app, sha: sha, branch: "main", dry_run: dry_run)
      Kamander::Ci::Launcher.new(launch: launch, host: "legion", user: "ci", ssh_client: @box,
        command_runner: runner, poll_interval: 0).call
      launch.reload
    end

    def git(*args)
      out, status = Open3.capture2("git", "-C", @repo, *args)
      assert status.success?, "git #{args.join(" ")} failed"
      out
    end
end
