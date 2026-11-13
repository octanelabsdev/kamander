require "test_helper"

class CiRunsControllerTest < ActionDispatch::IntegrationTest
  teardown { Kamander::Kamal.ssh_client = nil }

  test "Evan opens CI and sees which step failed, which runs signed off, and which were dry runs" do
    stub_box ci_records(
      record("beanlink-20261112T100000Z-12", app: "beanlink", status: "failed", steps: [
        { name: "Style: Ruby", result: "passed", took: "1s" }, { name: "Tests: Rails", result: "failed", took: "50s" }
      ]),
      record("fixxer-20261112T090000Z-11", status: "passed", dry_run: true),
      record("fixxer-20261112T080000Z-10", status: "passed", steps: [
        { name: "Tests: Rails", result: "passed", took: "40s" }, { name: "Signoff: All systems go.", result: "passed", took: "1s" }
      ])
    )

    get ci_runs_url

    assert_response :success
    assert_select "#ci_run_beanlink-20261112T100000Z-12" do
      assert_select "a[href=?]", ci_run_path("beanlink-20261112T100000Z-12"), text: "beanlink"
      assert_select "[data-step-result=failed]", text: "Failed at Tests: Rails"
      assert_select "[data-step]", count: 2
      assert_select "[data-signed-off]", count: 0
    end
    assert_select "#ci_run_fixxer-20261112T090000Z-11", text: /dry run/
    assert_select "#ci_run_fixxer-20261112T080000Z-10 [data-signed-off]", text: /signed/
  end

  test "a run still going sits in the In progress block above the finished ones" do
    id = "fixxer-20261112T100000Z-12"
    Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id, status: "running"), record("fixxer-20261112T090000Z-11"), live: [ id ])

    get ci_runs_url

    assert_select "#ci_in_progress #ci_run_#{id}"
    assert_select "#ci_in_progress #ci_run_fixxer-20261112T090000Z-11", count: 0
  end

  test "Evan filters CI to one app with a single click on its tab" do
    managed_apps(:track_planner).update!(ci_name: "fixxer")
    fake = stub_box(ci_records(record("fixxer-20261112T090000Z-11")))

    get ci_runs_url(app: "fixxer")

    assert_response :success
    assert_includes fake.calls.sole.command, "fixxer-[0-9]*.json"
    assert_select "nav a[aria-current=page][href=?]", ci_runs_path(app: "fixxer"), text: "fixxer"
    assert_select "nav a[href=?]", ci_runs_path, text: "All apps"
  end

  test "filtered to one app, Evan sees each test step's time across runs and spots the slowdown" do
    timed = ->(id, started, seconds) do
      record(id, steps: [ { name: "Tests: System", result: "passed", took: "#{seconds}s", seconds: seconds } ]).merge(started_at: started)
    end
    Kamander::Kamal.ssh_client = FakeCiBox.serving(
      timed.("fixxer-20261112T080000Z-1", "2026-11-12T08:00:00Z", 30.0),
      timed.("fixxer-20261112T090000Z-2", "2026-11-12T09:00:00Z", 31.0),
      timed.("fixxer-20261112T100000Z-3", "2026-11-12T10:00:00Z", 943.2)
    )

    get ci_runs_url(app: "fixxer")

    assert_select "#ci_step_times [data-step-times='Tests: System']" do
      assert_select "a[data-seconds]", count: 3
      assert_select "a[href=?].bg-amber-500", ci_run_path("fixxer-20261112T100000Z-3")
      assert_select "[data-latest].text-amber-400", text: /15m 43s/
    end
  end

  test "all apps shows no step times; they only make sense for one app" do
    stub_box ci_records(record("fixxer-20261112T090000Z-11"))

    get ci_runs_url

    assert_select "#ci_step_times", count: 0
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

  test "Evan opens a finished run and sees its slowest tests, slowest first, with file and line" do
    id = "fixxer-20261112T090000Z-11"
    Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id).merge(slowest: {
      "Tests: Rails" => [ { test: "CardTest#test_price", seconds: 1.5, file: "test/models/card_test.rb", line: 12 } ],
      "Tests: System" => [ { test: "CheckoutTest#test_pay", seconds: 31.25, file: "test/system/checkout_test.rb", line: 8 } ]
    }))

    get ci_run_url(id)

    assert_select "#ci_slowest_tests [data-slow-test]", count: 2 do |rows|
      assert_match(/pay.*31\.25s.*checkout_test\.rb:8/m, rows.first.text)
      assert_select rows.first, "[title=?]", "CheckoutTest#test_pay"
    end
  end

  test "an old run without timing says it wasn't recorded instead of showing nothing" do
    id = "fixxer-20261112T090000Z-11"
    Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id))

    get ci_run_url(id)

    assert_select "#ci_slowest_tests", count: 0
    assert_select "p", text: /predates ci-box's test timing/
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

  test "a live run offers Cancel, with a confirm naming the run" do
    id = "fixxer-20261112T090000Z-11"
    Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id, status: "running"), live: [ id ])

    get ci_run_url(id)

    assert_select "form[action=?] button[data-turbo-confirm*=?]", cancel_ci_run_path(id), "Cancel fixxer main abc1234", text: "Cancel run"
  end

  test "a finished run has no Cancel" do
    id = "fixxer-20261112T090000Z-11"
    Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id, status: "passed"))

    get ci_run_url(id)

    assert_select "form[action=?]", cancel_ci_run_path(id), count: 0
  end

  test "Evan cancels a live run: one kill for that pid, then back on the run with a notice" do
    id = "fixxer-20261112T090000Z-11"
    box = Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id, status: "running").merge(pid: 4242), live: [ id ],
      responses: { "ci-box.test" => "#{Kamander::Ci::Canceller::SENT}\n" })

    post cancel_ci_run_url(id)

    assert_redirected_to ci_run_path(id)
    assert_match(/Cancel sent/, flash[:notice])
    kills = box.calls.select { |call| call.command.include?("kill -TERM 4242") }
    assert_equal 1, kills.size
    assert_equal "ci", kills.sole.user
  end

  test "cancelling a run that already finished sends nothing to the box" do
    id = "fixxer-20261112T090000Z-11"
    box = Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id, status: "passed"))

    post cancel_ci_run_url(id)

    assert_redirected_to ci_run_path(id)
    assert_match(/nothing to cancel/, flash[:alert])
    assert_empty box.calls.select { |call| call.command.include?("kill") }
  end

  test "a refused cancel shows the box's reason and is not retried" do
    id = "fixxer-20261112T090000Z-11"
    box = Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id, status: "running").merge(pid: 4242), live: [ id ],
      responses: { "ci-box.test" => "kamander: pid 4242 is not this run any more\n" })

    post cancel_ci_run_url(id)

    assert_equal "kamander: pid 4242 is not this run any more", flash[:alert]
    assert_equal 1, box.calls.count { |call| call.command.include?("kill") }
  end

  test "a run of a repo with a dot in its name opens and can be cancelled" do
    id = "foo.dev-20261112T090000Z-11"
    Kamander::Kamal.ssh_client = FakeCiBox.serving(record(id, app: "foo.dev", status: "running").merge(pid: 4242), live: [ id ],
      responses: { "ci-box.test" => "#{Kamander::Ci::Canceller::SENT}\n" })

    get ci_run_url(id)
    assert_response :success
    assert_select "h1", text: "foo.dev"

    post cancel_ci_run_url(id)
    assert_redirected_to ci_run_path(id)
    assert_match(/Cancel sent/, flash[:notice])
  end

  test "a test step recorded at 0 seconds doesn't break the step times chart" do
    zero = { name: "Tests: Seeds", result: "passed", took: "0s", seconds: 0.0 }
    Kamander::Kamal.ssh_client = FakeCiBox.serving(
      record("fixxer-20261112T090000Z-1", steps: [ zero ]),
      record("fixxer-20261112T100000Z-2", steps: [ zero ]).merge(started_at: "2026-11-12T10:00:00Z")
    )

    get ci_runs_url(app: "fixxer")

    assert_response :success
  end

  test "a run id the box doesn't have is a 404" do
    stub_box ci_records

    get ci_run_url("fixxer-20261112T000000Z-00")

    assert_response :not_found
  end

  private

    def stub_box(response)
      Kamander::Kamal.ssh_client = FakeCiBox.new(responses: { "ci-box.test" => response })
    end

    def ci_records(*records)
      records.map(&:to_json).join("\n") + "\n---\n"
    end

    def record(id, **attributes) = FakeCiBox.record(id, **attributes)
end
