require "test_helper"

class CiLaunchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @repo = Dir.mktmpdir
    system("git", "-C", @repo, "init", "-q", exception: true)
    system("git", "-C", @repo, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "x", exception: true)
    @head = Kamander::Ci::Checkout.read(@repo)
    @app = managed_apps(:track_planner)
    @app.update!(repo_path: @repo, ci_name: "track-planner")
  end

  teardown { FileUtils.remove_entry(@repo) }

  test "the app page offers Dry run, and Run CI asks to confirm naming the branch and commit it will sign" do
    get managed_app_url(@app)

    assert_select "#ci_panel" do
      assert_select "form[action=?] input[name=sha][value=?]", managed_app_ci_launches_path(@app), @head.sha, count: 2
      assert_select "button", text: "Dry run"
      assert_select "button[data-turbo-confirm*=?]", "#{@head.branch} #{@head.short_sha}", text: "Run CI"
      assert_select "button[data-turbo-confirm*=?]", "stamps gh signoff"
    end
  end

  test "an app with no GitHub origin has no CI panel" do
    @app.update!(ci_name: nil)

    get managed_app_url(@app)

    assert_select "#ci_panel", count: 0
  end

  test "Evan clicks Dry run and lands on the launch page while the job starts remote-ci" do
    assert_enqueued_with(job: CiLaunchJob) do
      post managed_app_ci_launches_url(@app), params: { sha: @head.sha, branch: @head.branch, dry_run: "1" }
    end

    launch = CiLaunch.sole
    assert launch.dry_run
    assert_equal @head.sha, launch.sha
    assert_redirected_to ci_launch_path(launch)

    follow_redirect!
    assert_select "#ci_launch_status", text: /waiting for the box/
  end

  test "Run CI records a real run for the confirmed commit" do
    post managed_app_ci_launches_url(@app), params: { sha: @head.sha, branch: @head.branch, dry_run: "0" }

    assert_not CiLaunch.sole.dry_run
  end

  test "a second click while CI is still starting is refused, so one click is one run" do
    @app.ci_launches.create!(sha: @head.sha)

    assert_no_enqueued_jobs(only: CiLaunchJob) do
      post managed_app_ci_launches_url(@app), params: { sha: @head.sha, dry_run: "1" }
    end

    assert_equal 1, CiLaunch.count
    assert_equal "CI is already starting for #{@app.display_label}.", flash[:alert]
  end

  test "a launch whose job died long ago no longer blocks Run CI; it is marked failed and a new one starts" do
    stale = @app.ci_launches.create!(sha: @head.sha, created_at: 10.minutes.ago)

    assert_enqueued_with(job: CiLaunchJob) do
      post managed_app_ci_launches_url(@app), params: { sha: @head.sha, dry_run: "1" }
    end

    assert stale.reload.failed?
    assert_includes stale.output, "gave up"
    assert_equal 2, @app.ci_launches.count
  end

  test "once the box has the run, the launch page sends Evan to it" do
    launch = @app.ci_launches.create!(sha: @head.sha, status: :started, run_id: "track-planner-20261112T100000Z-12")

    get ci_launch_url(launch)

    assert_redirected_to ci_run_path("track-planner-20261112T100000Z-12")
  end

  test "a refused launch shows remote-ci's own words" do
    launch = @app.ci_launches.create!(sha: @head.sha, status: :failed, output: "remote-ci: commit abc1234 is not on origin; push it first\n")

    get ci_launch_url(launch)

    assert_select "[role=alert]", text: "CI did not start."
    assert_select "pre", text: /push it first/
  end
end
