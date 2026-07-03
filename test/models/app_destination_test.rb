require "test_helper"

class AppDestinationTest < ActiveSupport::TestCase
  test "requires a config_file" do
    destination = AppDestination.new(managed_app: managed_apps(:track_planner))
    assert_not destination.valid?
    assert_includes destination.errors[:config_file], "can't be blank"
  end

  test "requires config_file to be unique within a managed app" do
    duplicate = AppDestination.new(managed_app: managed_apps(:track_planner), config_file: "deploy.production.yml")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:config_file], "has already been taken"

    different_app = AppDestination.new(managed_app: managed_apps(:old_project), config_file: "deploy.production.yml")
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
    assert app_destinations(:contractor_link_base).base?
    assert_not app_destinations(:track_planner_production).base?
  end

  test "a base destination counts as production" do
    assert app_destinations(:contractor_link_base).production?
  end

  test "a destination named prod counts as production" do
    destination = app_destinations(:track_planner_staging)
    destination.name = "prod"
    assert destination.production?
  end

  test "staging does not count as production" do
    assert_not app_destinations(:track_planner_staging).production?
  end

  test "effective_ssh_user prefers the cached ssh_user over the default" do
    destination = app_destinations(:track_planner_production)
    destination.ssh_user = "custom-user"
    assert_equal "custom-user", destination.effective_ssh_user
  end

  test "effective_ssh_user falls back to the setting default when blank" do
    destination = app_destinations(:contractor_link_base)
    assert_nil destination.ssh_user
    assert_equal Setting.current.default_ssh_user, destination.effective_ssh_user
  end

  test "a destination's effective service prefers its own captured service name" do
    destination = app_destinations(:contractor_link_base)
    destination.service_name = "contractor_link_staging"
    assert_equal "contractor_link_staging", destination.effective_service
  end

  test "falls back to the app's service name when the destination's is blank" do
    destination = app_destinations(:contractor_link_base)
    destination.service_name = ""
    assert_equal managed_apps(:contractor_link).service_name, destination.effective_service
  end
end
