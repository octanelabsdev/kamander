require "test_helper"

class Kamander::Kamal::StatusReaderTest < ActiveSupport::TestCase
  test "a running web container reports the destination as running" do
    destination = destination_for("solo_app", servers: { "web" => [ "10.0.0.1" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.1" => docker_ps([ container(name: "solo_app-web-abc1234", state: "running", status: "Up 10 minutes") ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal :running, report.state
    web = report.containers.find { |c| c.label == "web" }
    assert_equal :running, web.state
    assert_equal "abc1234", web.version
  end

  test "a stopped worker container reports the destination as partial" do
    destination = destination_for("solo_app", servers: { "web" => [ "10.0.0.2" ], "worker" => [ "10.0.0.2" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.2" => docker_ps([
        container(name: "solo_app-web-abc1234", state: "running", status: "Up 10 minutes"),
        container(name: "solo_app-worker-abc1234", state: "exited", status: "Exited (0) 5 minutes ago")
      ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal :partial, report.state
    worker = report.containers.find { |c| c.label == "worker" }
    assert_equal :exited, worker.state
  end

  test "matching ignores the trailing version SHA" do
    destination = destination_for("multi_app", name: "production", servers: { "web" => [ "10.0.0.3" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.3" => docker_ps([ container(name: "multi_app-web-production-9f8e7d6", state: "running", status: "Up 1 hour") ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal :running, report.state
    assert_equal "9f8e7d6", report.containers.find { |c| c.label == "web" }.version
  end

  test "an accessory that is down is reflected in the containers" do
    destination = destination_for("acc_app", servers: { "web" => [ "10.0.0.4" ] }, accessory_names: [ "db" ])
    fake = FakeSshClient.new(responses: {
      "10.0.0.4" => docker_ps([
        container(name: "acc_app-web-a1a1a1a", state: "running", status: "Up 1 hour"),
        container(name: "acc_app-db", state: "exited", status: "Exited (1) 2 minutes ago")
      ])
    })

    report = call_reader([ destination ], fake).first

    db = report.containers.find { |c| c.label == "db" }
    assert_equal :accessory, db.kind
    assert_equal :exited, db.state
    assert_equal :partial, report.state
  end

  test "an unreachable host reports that destination as unreachable without affecting others" do
    reachable = destination_for("up_app", servers: { "web" => [ "10.0.0.5" ] })
    unreachable = destination_for("down_app", servers: { "web" => [ "10.0.0.6" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.5" => docker_ps([ container(name: "up_app-web-b2b2b2b", state: "running", status: "Up 1 hour") ]),
      "10.0.0.6" => :unreachable
    })

    reports = call_reader([ reachable, unreachable ], fake).index_by(&:app_destination_id)

    assert_equal :running, reports.fetch(reachable.id).state
    assert_equal :unreachable, reports.fetch(unreachable.id).state
    assert_empty reports.fetch(unreachable.id).containers
    assert reports.fetch(unreachable.id).error.present?
  end

  test "destinations sharing a host trigger exactly one ssh call" do
    track_planner = destination_for("track-planner", name: "production", servers: { "web" => [ "203.0.113.10" ] })
    contractor_link = destination_for("contractor_link", name: "production", servers: { "web" => [ "203.0.113.10" ] },
      accessory_names: [ "db" ])
    fake = FakeSshClient.new(responses: { "203.0.113.10" => file_fixture("docker_ps/shared_host.txt").read })

    reports = call_reader([ track_planner, contractor_link ], fake).index_by(&:app_destination_id)

    assert_equal 1, fake.calls.count { |call| call.host == "203.0.113.10" }
    assert_equal :running, reports.fetch(track_planner.id).state
    assert_equal :running, reports.fetch(contractor_link.id).state
  end

  test "the host's kamal-proxy is included in the containers" do
    destination = destination_for("proxy_app", servers: { "web" => [ "10.0.0.7" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.7" => docker_ps([ container(name: "kamal-proxy", state: "running", status: "Up 6 days") ])
    })

    report = call_reader([ destination ], fake).first

    proxy = report.containers.find { |c| c.label == "kamal-proxy" }
    assert_equal :proxy, proxy.kind
    assert_equal :running, proxy.state
    # kamal-proxy is informational only — the missing web role still drives the state.
    assert_equal :down, report.state
  end

  test "an expected container that is absent on its server is reported absent, not silently dropped" do
    destination = destination_for("gap_app", servers: { "web" => [ "10.0.0.8" ], "worker" => [ "10.0.0.9" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.8" => docker_ps([ container(name: "gap_app-web-c3c3c3c", state: "running", status: "Up 1 hour") ]),
      "10.0.0.9" => docker_ps([])
    })

    report = call_reader([ destination ], fake).first

    web = report.containers.find { |c| c.label == "web" }
    worker = report.containers.find { |c| c.label == "worker" }
    assert_equal :running, web.state
    assert_equal :absent, worker.state
    assert_nil worker.name
  end

  test "each observed container is tagged with the host it was seen on" do
    destination = destination_for("multi_host_app", servers: { "web" => [ "10.0.0.10" ], "worker" => [ "10.0.0.11" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.10" => docker_ps([
        container(name: "multi_host_app-web-d4d4d4d", state: "running", status: "Up 1 hour"),
        container(name: "kamal-proxy", state: "running", status: "Up 6 days")
      ]),
      "10.0.0.11" => docker_ps([ container(name: "multi_host_app-worker-d4d4d4d", state: "running", status: "Up 1 hour") ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal "10.0.0.10", report.containers.find { |c| c.label == "web" }.host
    assert_equal "10.0.0.11", report.containers.find { |c| c.label == "worker" }.host
    assert_equal "10.0.0.10", report.containers.find { |c| c.label == "kamal-proxy" }.host
  end

  private

    def call_reader(destinations, fake_ssh_client)
      Kamander::Kamal::StatusReader.new(destinations: destinations, ssh_client: fake_ssh_client).call
    end

    def destination_for(service_name, name: nil, servers:, accessory_names: [])
      managed_app = ManagedApp.create!(
        repo_path: "/tmp/#{service_name}-#{name}-#{SecureRandom.hex(4)}",
        service_name: service_name,
        discovered_at: Time.current,
        last_scanned_at: Time.current
      )
      managed_app.app_destinations.create!(
        name: name,
        config_file: name ? "deploy.#{name}.yml" : "deploy.yml",
        servers: servers,
        accessory_names: accessory_names,
        ssh_user: "deploy"
      )
    end

    def container(name:, state:, status:, image: "kamander/app:latest")
      { "Names" => name, "State" => state, "Status" => status, "Image" => image }
    end

    def docker_ps(containers)
      containers.map(&:to_json).join("\n")
    end
end
