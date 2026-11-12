require "application_system_test_case"

class LaunchingCiTest < ApplicationSystemTestCase
  RUN_ID = "track-planner-20261112T100000Z-12".freeze

  setup do
    @original_ssh_client = Kamander::Kamal.ssh_client
    @original_command_runner = Kamander::Kamal.command_runner
    @repo = Dir.mktmpdir
    system("git", "-C", @repo, "init", "-q", exception: true)
    system("git", "-C", @repo, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "x", exception: true)
    @app = managed_apps(:track_planner)
    @app.update!(repo_path: @repo, ci_name: "track-planner")
  end

  teardown do
    Kamander::Kamal.ssh_client = @original_ssh_client
    Kamander::Kamal.command_runner = @original_command_runner
    FileUtils.remove_entry(@repo)
  end

  test "Evan starts a dry run from the app page and ends up on the run the box recorded" do
    sha = Kamander::Ci::Checkout.read(@repo).sha
    box = Kamander::Kamal.ssh_client = FakeCiBox.serving
    Kamander::Kamal.command_runner = FakeCommandRunner.new(responses: { %w[remote-ci --dry-run] => {
      on_spawn: -> { box.records << FakeCiBox.record(RUN_ID, app: "track-planner", sha: sha) }
    } })

    visit managed_app_path(@app)
    within("#ci_panel") { click_on "Dry run" }

    assert_text "waiting for the box"
    CiLaunchJob.perform_now(CiLaunch.sole)

    assert_selector "h1", text: "track-planner"
    assert_current_path ci_run_path(RUN_ID)
  end

  test "Run CI asks first, and cancelling the confirm starts nothing" do
    visit managed_app_path(@app)

    dismiss_confirm(/stamps gh signoff/) { within("#ci_panel") { click_on "Run CI" } }

    assert_equal 0, CiLaunch.count
  end
end
