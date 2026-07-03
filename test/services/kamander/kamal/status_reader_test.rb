require "test_helper"

class Kamander::Kamal::StatusReaderTest < ActiveSupport::TestCase
  test "a running web container reports the destination as running" do
    destination = destination_for("solo_app", servers: { "web" => [ "10.0.0.1" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.1" => docker_ps([ container(name: "solo_app-web-#{full_sha}", state: "running", status: "Up 10 minutes",
                                           service: "solo_app", role: "web", destination: "") ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal :running, report.state
    web = report.containers.find { |c| c.role == "web" }
    assert_equal :running, web.state
  end

  test "a stopped worker container reports the destination as partial" do
    destination = destination_for("solo_app", servers: { "web" => [ "10.0.0.2" ], "worker" => [ "10.0.0.2" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.2" => docker_ps([
        container(name: "solo_app-web-#{full_sha}", state: "running", status: "Up 10 minutes",
                  service: "solo_app", role: "web", destination: ""),
        container(name: "solo_app-worker-#{full_sha}", state: "exited", status: "Exited (0) 5 minutes ago",
                  service: "solo_app", role: "worker", destination: "")
      ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal :partial, report.state
    worker = report.containers.find { |c| c.role == "worker" }
    assert_equal :exited, worker.state
  end

  test "matching ignores the trailing version SHA" do
    destination = destination_for("multi_app", name: "production", servers: { "web" => [ "10.0.0.3" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.3" => docker_ps([ container(name: "multi_app-web-production-#{full_sha}", state: "running", status: "Up 1 hour",
                                           service: "multi_app", role: "web", destination: "production") ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal :running, report.state
    assert_equal :running, report.containers.find { |c| c.role == "web" }.state
  end

  test "an accessory that is down is reflected in the containers" do
    destination = destination_for("acc_app", servers: { "web" => [ "10.0.0.4" ] }, accessory_names: [ "db" ])
    fake = FakeSshClient.new(responses: {
      "10.0.0.4" => docker_ps([
        container(name: "acc_app-web-#{full_sha}", state: "running", status: "Up 1 hour",
                  service: "acc_app", role: "web", destination: ""),
        container(name: "acc_app-db", state: "exited", status: "Exited (1) 2 minutes ago", service: "acc_app-db")
      ])
    })

    report = call_reader([ destination ], fake).first

    db = report.containers.find { |c| c.kind == :accessory }
    assert_equal :exited, db.state
    assert_equal :partial, report.state
  end

  test "an unreachable host reports that destination as unreachable without affecting others" do
    reachable = destination_for("up_app", servers: { "web" => [ "10.0.0.5" ] })
    unreachable = destination_for("down_app", servers: { "web" => [ "10.0.0.6" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.5" => docker_ps([ container(name: "up_app-web-#{full_sha}", state: "running", status: "Up 1 hour",
                                           service: "up_app", role: "web", destination: "") ]),
      "10.0.0.6" => :unreachable
    })

    reports = call_reader([ reachable, unreachable ], fake).index_by(&:app_destination_id)

    assert_equal :running, reports.fetch(reachable.id).state
    assert_equal :unreachable, reports.fetch(unreachable.id).state
    assert_empty reports.fetch(unreachable.id).containers
    assert reports.fetch(unreachable.id).error.present?
  end

  test "destinations sharing a host trigger exactly one ssh call" do
    track_planner = destination_for("track-planner", name: "production", servers: { "web" => [ "203.0.113.10" ] },
      accessory_names: [ "db" ])
    contractor_link = destination_for("contractor_link", name: "production", servers: { "web" => [ "203.0.113.10" ] })
    fake = FakeSshClient.new(responses: { "203.0.113.10" => file_fixture("docker_ps/shared_host.txt").read })

    reports = call_reader([ track_planner, contractor_link ], fake).index_by(&:app_destination_id)

    assert_equal 1, fake.calls.count { |call| call.host == "203.0.113.10" }
    assert_equal :running, reports.fetch(track_planner.id).state
    assert_equal :running, reports.fetch(contractor_link.id).state
  end

  test "the host's kamal-proxy is included in the containers" do
    destination = destination_for("proxy_app", servers: { "web" => [ "10.0.0.7" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.7" => docker_ps([ container(name: "kamal-proxy", state: "running", status: "Up 6 days", service: "kamal-proxy") ])
    })

    report = call_reader([ destination ], fake).first

    proxy = report.containers.find { |c| c.kind == :proxy }
    assert_equal :running, proxy.state
    # kamal-proxy is informational only — the missing web role still drives the state.
    assert_equal :down, report.state
  end

  test "a mid-deploy role slot reports both the old and new containers with their versions" do
    old_sha = full_sha
    new_sha = "b2c3d4e5f60718293a4b5c6d7e8f901234567ab"[0, 40]
    destination = destination_for("mid_deploy_app", servers: { "web" => [ "10.0.0.25" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.25" => docker_ps([
        container(name: "mid_deploy_app-web-#{old_sha}", state: "exited", status: "Exited (0) 2 minutes ago",
                  image: "kamander/mid_deploy_app:#{old_sha}", service: "mid_deploy_app", role: "web", destination: ""),
        container(name: "mid_deploy_app-web-#{new_sha}", state: "running", status: "Up 1 minute",
                  image: "kamander/mid_deploy_app:#{new_sha}", service: "mid_deploy_app", role: "web", destination: "")
      ])
    })

    report = call_reader([ destination ], fake).first

    web_containers = report.containers.select { |c| c.role == "web" }
    assert_equal 2, web_containers.size
    assert_equal [ old_sha, new_sha ].sort, web_containers.map(&:version).sort
    assert_equal :exited, web_containers.find { |c| c.version == old_sha }.state
    assert_equal :running, web_containers.find { |c| c.version == new_sha }.state
    assert_equal :running, report.state
  end

  test "an expected container that is absent on its server is reported absent, not silently dropped" do
    destination = destination_for("gap_app", servers: { "web" => [ "10.0.0.8" ], "worker" => [ "10.0.0.9" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.8" => docker_ps([ container(name: "gap_app-web-#{full_sha}", state: "running", status: "Up 1 hour",
                                           service: "gap_app", role: "web", destination: "") ]),
      "10.0.0.9" => docker_ps([])
    })

    report = call_reader([ destination ], fake).first

    web = report.containers.find { |c| c.role == "web" }
    worker = report.containers.find { |c| c.role == "worker" }
    assert_equal :running, web.state
    assert_equal :absent, worker.state
    assert_nil worker.name
  end

  test "each observed container is tagged with the host it was seen on" do
    destination = destination_for("multi_host_app", servers: { "web" => [ "10.0.0.10" ], "worker" => [ "10.0.0.11" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.10" => docker_ps([
        container(name: "multi_host_app-web-#{full_sha}", state: "running", status: "Up 1 hour",
                  service: "multi_host_app", role: "web", destination: ""),
        container(name: "kamal-proxy", state: "running", status: "Up 6 days", service: "kamal-proxy")
      ]),
      "10.0.0.11" => docker_ps([ container(name: "multi_host_app-worker-#{full_sha}", state: "running", status: "Up 1 hour",
                                            service: "multi_host_app", role: "worker", destination: "") ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal "10.0.0.10", report.containers.find { |c| c.role == "web" }.host
    assert_equal "10.0.0.11", report.containers.find { |c| c.role == "worker" }.host
    assert_equal "10.0.0.10", report.containers.find { |c| c.kind == :proxy }.host
  end

  test "a plain-deploy container is claimed by the sole destination with that service" do
    destination = destination_for("solo_service_app", name: "production", servers: { "web" => [ "10.0.0.20" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.20" => docker_ps([ container(name: "solo_service_app-web-#{full_sha}", state: "running", status: "Up 1 hour",
                                            service: "solo_service_app", role: "web", destination: "") ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal :running, report.state
    assert_equal :running, report.containers.find { |c| c.role == "web" }.state
  end

  test "a service-override destination is matched by its own effective service and destination label" do
    staging = destination_for("contractor_link_staging", name: "staging", servers: { "web" => [ "10.0.0.21" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.21" => docker_ps([ container(name: "contractor_link_staging-web-staging-#{full_sha}", state: "running",
        status: "Up 1 hour", service: "contractor_link_staging", role: "web", destination: "staging") ])
    })

    report = call_reader([ staging ], fake).first

    web = report.containers.find { |c| c.role == "web" }
    assert_equal :running, web.state
    assert_equal "staging", web.destination
    assert_equal "contractor_link_staging", web.service
  end

  test "an accessory is matched by its destination's effective service, even under an override" do
    staging = destination_for("contractor_link_staging", name: "staging", servers: { "web" => [ "10.0.0.22" ] },
      accessory_names: [ "cache" ])
    fake = FakeSshClient.new(responses: {
      "10.0.0.22" => docker_ps([
        container(name: "contractor_link_staging-web-staging-#{full_sha}", state: "running", status: "Up 1 hour",
                  service: "contractor_link_staging", role: "web", destination: "staging"),
        container(name: "contractor_link_staging-cache", state: "running", status: "Up 1 hour",
                  service: "contractor_link_staging-cache")
      ])
    })

    report = call_reader([ staging ], fake).first

    cache = report.containers.find { |c| c.kind == :accessory }
    assert_equal :running, cache.state
    assert_equal "contractor_link_staging-cache", cache.service
    assert_equal :running, report.state
  end

  test "an unattributed running container is reported, not dropped" do
    destination = destination_for("known_app", servers: { "web" => [ "10.0.0.23" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.23" => docker_ps([
        container(name: "known_app-web-#{full_sha}", state: "running", status: "Up 1 hour",
                  service: "known_app", role: "web", destination: ""),
        container(name: "mystery_app-web-#{full_sha}", state: "running", status: "Up 30 minutes",
                  service: "mystery_app", role: "web", destination: "")
      ])
    })

    report = call_reader([ destination ], fake).first

    unattributed = report.containers.find { |c| c.kind == :unattributed }
    assert_equal :running, unattributed.state
    assert_equal "mystery_app", unattributed.service
    # An unattributed container never gates state — the known app is still running cleanly.
    assert_equal :running, report.state
  end

  test "deployed version is read full-length from the image tag" do
    destination = destination_for("versioned_app", servers: { "web" => [ "10.0.0.24" ] })
    fake = FakeSshClient.new(responses: {
      "10.0.0.24" => docker_ps([ container(name: "versioned_app-web-#{full_sha}", state: "running", status: "Up 1 hour",
                                            image: "kamander/versioned_app:#{full_sha}",
                                            service: "versioned_app", role: "web", destination: "") ])
    })

    report = call_reader([ destination ], fake).first

    assert_equal full_sha, report.containers.find { |c| c.role == "web" }.version
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
        service_name: service_name,
        config_file: name ? "deploy.#{name}.yml" : "deploy.yml",
        servers: servers,
        accessory_names: accessory_names,
        ssh_user: "deploy"
      )
    end

    def container(name:, state:, status:, service:, role: nil, destination: nil, image: "kamander/app:latest")
      { "Names" => name, "State" => state, "Status" => status, "Image" => image, "Labels" => labels(service, role, destination) }
    end

    def labels(service, role, destination)
      [ "service=#{service}", role && "role=#{role}", !destination.nil? && "destination=#{destination}" ].compact.join(",")
    end

    def docker_ps(containers)
      containers.map(&:to_json).join("\n")
    end

    def full_sha
      "a1b2c3d4e5f60718293a4b5c6d7e8f901234567a"[0, 40]
    end
end
