require "test_helper"

class CiRunsControllerTest < ActionDispatch::IntegrationTest
  teardown { Kamander::Kamal.ssh_client = nil }

  test "Evan opens CI and sees each run with its failing step highlighted" do
    stub_box ci_records(
      record("beanlink-20261112T100000Z-12", app: "beanlink", status: "failed", steps: [
        { name: "Style: Ruby", result: "passed", took: "1s" }, { name: "Tests: Rails", result: "failed", took: "50s" }
      ]),
      record("fixxer-20261112T090000Z-11", status: "passed", dry_run: true)
    )

    get ci_runs_url

    assert_response :success
    assert_select "tr#ci_run_beanlink-20261112T100000Z-12" do
      assert_select "td", text: /beanlink/
      assert_select "[data-step-result=failed]", text: /Tests: Rails/
      assert_select "a[href=?]", ci_run_path("beanlink-20261112T100000Z-12")
    end
    assert_select "tr#ci_run_fixxer-20261112T090000Z-11", text: /dry run/
  end

  test "filtering the CI page by app asks the box for only that app's runs" do
    fake = stub_box(ci_records(record("fixxer-20261112T090000Z-11")))

    get ci_runs_url(app: "fixxer")

    assert_response :success
    assert_includes fake.calls.sole.command, "fixxer-[0-9]*.json"
  end

  test "CI box unreachable shows the error and the rest of Kamander still works" do
    stub_box :unreachable

    get ci_runs_url
    assert_response :success
    assert_select "[role=alert]", text: /CI box unreachable.*connection unreachable/m

    get root_url
    assert_response :success
  end

  test "with no CI host set, the CI page sends Evan to settings and the nav hides it" do
    Setting.current.update!(ci_host: nil)

    get ci_runs_url
    assert_redirected_to edit_setting_path

    get root_url
    assert_select "nav a[href=?]", ci_runs_path, count: 0
    assert_select "turbo-frame#latest_ci", count: 0
  end

  test "Evan opens a finished run and sees its steps and log" do
    stub_box ci_records(record("fixxer-20261112T090000Z-11", status: "failed", steps: [
      { name: "Tests: Rails", result: "failed", took: "50s" }
    ]))
    Kamander::Kamal.ssh_client.log_output = "Running 162 tests\n1 failure\n"

    get ci_run_url("fixxer-20261112T090000Z-11")

    assert_response :success
    assert_select "h1", text: /fixxer/
    assert_select "[data-step-result=failed]", text: /Tests: Rails/
    assert_select "pre", text: /1 failure/
  end

  test "with several runs on the box, Evan opens the one he clicked" do
    Kamander::Kamal.ssh_client = FakeCiBox.serving(
      record("beanlink-20261112T100000Z-12", app: "beanlink"),
      record("fixxer-20261112T090000Z-11")
    )

    get ci_run_url("beanlink-20261112T100000Z-12")

    assert_response :success
    assert_select "h1", text: "beanlink"
  end

  test "Evan loads Latest CI on the dashboard and sees each app's newest run in one call to the box" do
    managed_apps(:track_planner).update!(ci_name: "track-planner")
    managed_apps(:contractor_link).update!(ci_name: "contractor_link")
    ManagedApp.create!(repo_path: "/tmp/quiet", service_name: "quiet", ci_name: "quiet", status: :managed,
      discovered_at: Time.current, last_scanned_at: Time.current)
    box = FakeCiBox.serving(
      record("track-planner-20261112T100000Z-2", app: "track-planner", status: "failed").merge(started_at: "2026-11-12T10:00:00Z"),
      record("track-planner-20261112T090000Z-1", app: "track-planner", status: "passed").merge(started_at: "2026-11-12T09:00:00Z")
    )
    Kamander::Kamal.ssh_client = box

    get root_url
    assert_select "turbo-frame#latest_ci a[href=?]", latest_ci_runs_path, text: "Load latest CI"

    get latest_ci_runs_url

    assert_response :success
    assert_select "turbo-frame#latest_ci" do
      assert_select "#latest_ci_track-planner a[href=?]", ci_run_path("track-planner-20261112T100000Z-2"), text: /failed/i
      assert_select "#latest_ci_quiet", text: /no recent runs/
      assert_select "#latest_ci_contractor_link", count: 0
    end
    assert_equal 1, box.calls.size
  end

  test "Latest CI with the box unreachable shows the error inside the strip" do
    managed_apps(:track_planner).update!(ci_name: "track-planner")
    stub_box :unreachable

    get latest_ci_runs_url

    assert_response :success
    assert_select "turbo-frame#latest_ci [role=alert]", text: /CI box unreachable.*connection unreachable/m
  end

  test "opening a live run starts following its log and subscribes the page to the stream" do
    id = "fixxer-20261112T090000Z-11"
    Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id, status: "running"), live: [ id ])
    Kamander::Kamal.ssh_client.log_output = "Running 162 tests\n"

    assert_enqueued_with(job: CiFollowJob, args: [ id ]) { get ci_run_url(id) }

    assert_response :success
    assert_select "turbo-cable-stream-source[signed-stream-name]", count: 1
    assert_select "pre#ci_run_log", text: /Running 162 tests/
  end

  test "opening a finished run neither follows it nor subscribes" do
    id = "fixxer-20261112T090000Z-11"
    Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id, status: "passed"))

    assert_no_enqueued_jobs(only: CiFollowJob) { get ci_run_url(id) }

    assert_select "turbo-cable-stream-source", count: 0
  end

  test "a run id the box doesn't have is a 404" do
    stub_box ci_records

    get ci_run_url("fixxer-20261112T000000Z-00")

    assert_response :not_found
  end

  private

    def stub_box(response)
      Kamander::Kamal.ssh_client = FakeCiBox.new(responses: { "legion" => response })
    end

    def ci_records(*records)
      records.map(&:to_json).join("\n") + "\n---\n"
    end

    def record(id, **attributes) = FakeCiBox.record(id, **attributes)
end
