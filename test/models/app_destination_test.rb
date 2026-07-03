require "test_helper"

class AppDestinationTest < ActiveSupport::TestCase
  test "requires a config_file" do
    destination = AppDestination.new(managed_app: managed_apps(:track_planner))
    assert_not destination.valid?
    assert_includes destination.errors[:config_file], "can't be blank"
  end

  test "requires config_file to be unique within a managed app" do
    duplicate = AppDestination.new(managed_app: managed_apps(:track_planner), config_file: "deploy.yml")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:config_file], "has already been taken"

    different_app = AppDestination.new(managed_app: managed_apps(:old_project), config_file: "deploy.yml")
    assert different_app.valid?
  end

  test "belongs to a managed app" do
    destination = app_destinations(:track_planner_production)
    assert_equal managed_apps(:track_planner), destination.managed_app
  end

  test "round-trips servers and accessory_names as JSON" do
    destination = app_destinations(:track_planner_production)
    assert_equal({ "web" => [ "203.0.113.10" ] }, destination.servers)
    assert_equal [ "db", "caddy", "domain-validator" ], destination.accessory_names
  end

  test "server_ips flattens and dedupes IPs across roles" do
    destination = app_destinations(:track_planner_production)
    destination.servers = { "web" => [ "203.0.113.10", "203.0.113.10" ], "job" => [ "203.0.113.11" ] }
    assert_equal [ "203.0.113.10", "203.0.113.11" ], destination.server_ips
  end

  test "the base config destination knows it is the base" do
    assert app_destinations(:track_planner_base).base?
    assert_not app_destinations(:track_planner_production).base?
  end
end
