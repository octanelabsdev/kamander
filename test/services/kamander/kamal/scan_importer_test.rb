require "test_helper"

class Kamander::Kamal::ScanImporterTest < ActiveSupport::TestCase
  test "importing scan results creates one discovered app per repo with cached service and destinations" do
    scanned_apps = [
      scanned_app(repo_path: "/tmp/repo_one", service_name: "repo-one", destinations: [
        scanned_destination(config_file: "deploy.yml", servers: { "web" => [ "1.2.3.4" ] }, proxy_host: "repo-one.example.com")
      ]),
      scanned_app(repo_path: "/tmp/repo_two", service_name: "repo-two", destinations: [
        scanned_destination(name: "production", config_file: "deploy.production.yml", accessory_names: [ "db" ])
      ])
    ]

    assert_difference [ "ManagedApp.count", "AppDestination.count" ], 2 do
      Kamander::Kamal::ScanImporter.new(scanned_apps).call
    end

    repo_one = ManagedApp.find_by(repo_path: "/tmp/repo_one")
    assert repo_one.discovered?
    assert_equal "repo-one", repo_one.service_name
    assert_equal "repo-one.example.com", repo_one.proxy_host
    assert_not_nil repo_one.discovered_at
    assert_not_nil repo_one.last_scanned_at
    assert_equal({ "web" => [ "1.2.3.4" ] }, repo_one.app_destinations.sole.servers)

    repo_two = ManagedApp.find_by(repo_path: "/tmp/repo_two")
    assert_equal [ "db" ], repo_two.app_destinations.sole.accessory_names
  end

  test "a destination that overrides service captures its own service name" do
    scanned = scanned_app(repo_path: "/tmp/repo_one", service_name: "repo-one", destinations: [
      scanned_destination(config_file: "deploy.yml", service_name: "repo-one"),
      scanned_destination(name: "staging", config_file: "deploy.staging.yml", service_name: "repo-one_staging")
    ])

    Kamander::Kamal::ScanImporter.new([ scanned ]).call

    managed_app = ManagedApp.find_by(repo_path: "/tmp/repo_one")
    base = managed_app.app_destinations.find_by(config_file: "deploy.yml")
    staging = managed_app.app_destinations.find_by(config_file: "deploy.staging.yml")
    assert_equal "repo-one", base.service_name
    assert_equal "repo-one_staging", staging.service_name
  end

  test "re-importing the same repo updates cached fields without duplicating the app or its destinations" do
    original = scanned_app(repo_path: "/tmp/repo_one", service_name: "repo-one", destinations: [
      scanned_destination(config_file: "deploy.yml", servers: { "web" => [ "1.2.3.4" ] }, proxy_host: "old.example.com")
    ])
    Kamander::Kamal::ScanImporter.new([ original ]).call
    managed_app = ManagedApp.find_by(repo_path: "/tmp/repo_one")
    original_discovered_at = managed_app.discovered_at
    original_scanned_at = managed_app.last_scanned_at

    travel 1.hour do
      rescanned = scanned_app(repo_path: "/tmp/repo_one", service_name: "repo-one", destinations: [
        scanned_destination(config_file: "deploy.yml", servers: { "web" => [ "5.6.7.8" ] }, proxy_host: "new.example.com")
      ])

      assert_no_difference [ "ManagedApp.count", "AppDestination.count" ] do
        Kamander::Kamal::ScanImporter.new([ rescanned ]).call
      end
    end

    managed_app.reload
    assert_equal "new.example.com", managed_app.proxy_host
    assert_equal({ "web" => [ "5.6.7.8" ] }, managed_app.app_destinations.sole.servers)
    assert_equal original_discovered_at, managed_app.discovered_at
    assert_operator managed_app.last_scanned_at, :>, original_scanned_at
  end

  test "re-importing does not revert an already-managed app back to discovered" do
    scanned = scanned_app(repo_path: "/tmp/repo_one", service_name: "repo-one", destinations: [
      scanned_destination(config_file: "deploy.yml")
    ])
    Kamander::Kamal::ScanImporter.new([ scanned ]).call
    ManagedApp.find_by(repo_path: "/tmp/repo_one").managed!

    Kamander::Kamal::ScanImporter.new([ scanned ]).call

    assert ManagedApp.find_by(repo_path: "/tmp/repo_one").managed?
  end

  test "importing an app with a parse error is skipped, not persisted" do
    errored = scanned_app(repo_path: "/tmp/broken_repo", service_name: nil, destinations: [],
      error: "could not parse config/deploy.yml")

    assert_no_difference [ "ManagedApp.count", "AppDestination.count" ] do
      Kamander::Kamal::ScanImporter.new([ errored ]).call
    end

    assert_nil ManagedApp.find_by(repo_path: "/tmp/broken_repo")
  end

  test "a transiently broken destination keeps its last-known-good cached servers" do
    scanned = scanned_app(repo_path: "/tmp/repo_one", service_name: "repo-one", destinations: [
      scanned_destination(name: "production", config_file: "deploy.production.yml",
        servers: { "web" => [ "1.2.3.4" ] }, accessory_names: [ "db" ])
    ])
    Kamander::Kamal::ScanImporter.new([ scanned ]).call
    managed_app = ManagedApp.find_by(repo_path: "/tmp/repo_one")

    broken = scanned_app(repo_path: "/tmp/repo_one", service_name: "repo-one", destinations: [
      scanned_destination(name: "production", config_file: "deploy.production.yml",
        servers: {}, accessory_names: [], error: "could not parse deploy.production.yml")
    ])

    assert_no_difference "AppDestination.count" do
      Kamander::Kamal::ScanImporter.new([ broken ]).call
    end

    destination = managed_app.app_destinations.sole
    assert_equal({ "web" => [ "1.2.3.4" ] }, destination.servers)
    assert_equal [ "db" ], destination.accessory_names
  end

  test "a destination removed from the repo disappears on the next import" do
    scanned = scanned_app(repo_path: "/tmp/repo_one", service_name: "repo-one", destinations: [
      scanned_destination(config_file: "deploy.yml"),
      scanned_destination(name: "staging", config_file: "deploy.staging.yml")
    ])
    Kamander::Kamal::ScanImporter.new([ scanned ]).call
    managed_app = ManagedApp.find_by(repo_path: "/tmp/repo_one")
    assert_equal 2, managed_app.app_destinations.count

    narrowed = scanned_app(repo_path: "/tmp/repo_one", service_name: "repo-one", destinations: [
      scanned_destination(config_file: "deploy.yml")
    ])

    assert_difference "AppDestination.count", -1 do
      Kamander::Kamal::ScanImporter.new([ narrowed ]).call
    end

    assert_equal [ "deploy.yml" ], managed_app.app_destinations.pluck(:config_file)
  end

  private

    def scanned_app(repo_path:, service_name: "app", destinations: [], error: nil)
      Kamander::Kamal::ScannedApp.new(repo_path: repo_path, service_name: service_name,
        destinations: destinations, error: error)
    end

    def scanned_destination(name: nil, service_name: "app", config_file: "deploy.yml", servers: {}, accessory_names: [],
      ssh_user: nil, proxy_host: nil, error: nil)
      Kamander::Kamal::ScannedDestination.new(name: name, service_name: service_name, config_file: config_file,
        servers: servers, accessory_names: accessory_names, ssh_user: ssh_user, proxy_host: proxy_host, error: error)
    end
end
