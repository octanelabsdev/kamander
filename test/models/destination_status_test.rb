require "test_helper"

class DestinationStatusTest < ActiveSupport::TestCase
  test "state enum covers unknown, running, partial, down, and unreachable" do
    status = destination_statuses(:track_planner_production_status)
    assert status.running?

    status.state = :unreachable
    assert status.unreachable?
  end

  test "a freshly checked status is not stale" do
    status = destination_statuses(:track_planner_production_status)
    status.checked_at = Time.current
    assert_not status.stale?
  end

  test "a status checked two minutes ago is stale" do
    status = destination_statuses(:track_planner_production_status)
    status.checked_at = 2.minutes.ago
    assert status.stale?
  end

  test "a status that has never been checked is stale" do
    status = destination_statuses(:track_planner_production_status)
    status.checked_at = nil
    assert status.stale?
  end

  test "round-trips containers as JSON" do
    status = destination_statuses(:track_planner_production_status)
    assert_equal 3, status.containers.size

    web = status.containers.find { |container| container["role"] == "web" }
    assert_equal "track-planner-web-production-63cea7c46926aa7437725417bd51fb40b95cb80a", web["name"]
    assert_equal "track-planner", web["service"]
    assert_equal "running", web["state"]
    assert_equal "63cea7c46926aa7437725417bd51fb40b95cb80a", web["version"]
  end
end
