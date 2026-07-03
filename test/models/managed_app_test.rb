require "test_helper"

class ManagedAppTest < ActiveSupport::TestCase
  test "requires a repo_path" do
    app = ManagedApp.new(service_name: "foo")
    assert_not app.valid?
    assert_includes app.errors[:repo_path], "can't be blank"
  end

  test "requires repo_path to be unique" do
    duplicate = ManagedApp.new(repo_path: managed_apps(:track_planner).repo_path, service_name: "duplicate")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:repo_path], "has already been taken"
  end

  test "defaults status to discovered" do
    app = ManagedApp.create!(repo_path: "/tmp/new-app", service_name: "new-app",
                              discovered_at: Time.current, last_scanned_at: Time.current)
    assert app.discovered?
  end

  test "managed scope returns only managed apps" do
    assert_equal [ managed_apps(:track_planner) ], ManagedApp.managed.to_a
  end

  test "ordered scope sorts by position then service_name" do
    assert_equal [ managed_apps(:contractor_link), managed_apps(:track_planner), managed_apps(:old_project) ],
      ManagedApp.ordered.to_a
  end

  test "destroying a managed app destroys its destinations" do
    app = managed_apps(:track_planner)
    assert_equal 2, app.app_destinations.count
    assert_difference "AppDestination.count", -2 do
      app.destroy
    end
  end

  test "display_label falls back to service_name when display_name is blank" do
    app = managed_apps(:track_planner)
    assert_nil app.display_name
    assert_equal app.service_name, app.display_label
  end

  test "status_rollup surfaces the worst state across destinations" do
    assert_equal "down", managed_apps(:track_planner).status_rollup
  end

  test "status_rollup treats a destination with no status row as unknown" do
    assert_equal "unknown", managed_apps(:contractor_link).status_rollup
  end

  test "status_rollup ranks unreachable above down" do
    destination_statuses(:track_planner_production_status).update!(state: :unreachable)
    assert_equal "unreachable", managed_apps(:track_planner).status_rollup
  end

  test "STATUS_SEVERITY tracks the DestinationStatus state enum's definition order" do
    assert_equal DestinationStatus.states.keys, ManagedApp::STATUS_SEVERITY
  end
end
