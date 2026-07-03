require "test_helper"

class Kamander::Kamal::ConfigScannerTest < ActiveSupport::TestCase
  test "discovers every repo with deploy.yml" do
    repo_names = scan.map { |app| File.basename(app.repo_path) }
    assert_equal %w[anchors_app empty_overlay_app erb_app malformed_app multi_dest_app
                    no_service_app partial_failure_app simple_app], repo_names.sort
  end

  test "base-only single destination" do
    destinations = app_for("simple_app").destinations
    assert_equal 1, destinations.size
    assert_nil destinations.first.name
    assert_equal "deploy.yml", destinations.first.config_file
    assert_equal({ "web" => [ "192.168.1.10" ] }, destinations.first.servers)
  end

  test "overlays deep-merge (production sees db+caddy accessories)" do
    destinations = app_for("multi_dest_app").destinations.index_by(&:name)

    production = destinations.fetch("production")
    assert_equal %w[caddy db domain-validator], production.accessory_names.sort
    assert_equal "multidest.example.com", production.proxy_host
    assert_equal "deploy", production.ssh_user

    staging = destinations.fetch("staging")
    assert_equal [], staging.accessory_names
    assert_equal "staging.multidest.example.com", staging.proxy_host
    assert_equal "deploy", staging.ssh_user
  end

  test "per-destination servers keyed by role" do
    destinations = app_for("multi_dest_app").destinations.index_by(&:name)

    assert_equal({ "web" => [ "10.0.1.10", "10.0.1.11" ], "worker" => [ "10.0.1.20" ] },
      destinations.fetch("production").servers)
    assert_equal({ "web" => [ "10.0.2.10" ] }, destinations.fetch("staging").servers)
  end

  test "ERB rendered before parse" do
    default_host = app_for("erb_app").destinations.first.servers["web"]
    assert_equal [ "10.0.0.9" ], default_host

    ENV["KAMANDER_TEST_HOST"] = "10.9.9.9"
    rendered_host = app_for("erb_app").destinations.first.servers["web"]
    assert_equal [ "10.9.9.9" ], rendered_host
  ensure
    ENV.delete("KAMANDER_TEST_HOST")
  end

  test "anchors/aliases resolve" do
    destination = app_for("anchors_app").destinations.first
    assert_equal "deploy", destination.ssh_user
    assert_equal destination.servers["web"], destination.servers["worker"]
  end

  test "malformed reported as error, others still scan" do
    results = scan

    malformed = results.find { |app| app.repo_path.end_with?("malformed_app") }
    assert malformed.error?
    assert_empty malformed.destinations

    simple = results.find { |app| app.repo_path.end_with?("simple_app") }
    assert_not simple.error?
    assert_equal 1, simple.destinations.size
  end

  test "missing service flagged" do
    app = app_for("no_service_app")
    assert_nil app.service_name
    assert app.error?
    assert_equal({ "web" => [ "10.0.5.5" ] }, app.destinations.first.servers)
  end

  test "an empty overlay merges as no overrides" do
    destination = app_for("empty_overlay_app").destinations.first

    assert_not destination.error?
    assert_equal "production", destination.name
    assert_equal({ "web" => [ "10.0.6.5" ] }, destination.servers)
  end

  test "one broken destination doesn't hide the rest of the app" do
    destinations = app_for("partial_failure_app").destinations.index_by(&:name)

    broken = destinations.fetch("broken")
    assert broken.error?
    assert_equal({}, broken.servers)

    production = destinations.fetch("production")
    assert_not production.error?
    assert_equal({ "web" => [ "10.0.7.10" ] }, production.servers)
    assert_equal "deploy", production.ssh_user
  end

  test "dir without deploy.yml ignored" do
    Dir.mktmpdir do |scan_root|
      FileUtils.mkdir_p(File.join(scan_root, "not_a_kamal_app"))
      assert_empty Kamander::Kamal::ConfigScanner.new(scan_root: scan_root).call
    end
  end

  private

    def scan
      Kamander::Kamal::ConfigScanner.new(scan_root: file_fixture("repos").to_s).call
    end

    def app_for(repo_name)
      scan.find { |app| app.repo_path.end_with?(repo_name) }
    end
end
