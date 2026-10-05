require "test_helper"

class ResourceUsagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_ssh_client = Kamander::Kamal.ssh_client
  end

  teardown do
    Kamander::Kamal.ssh_client = @original_ssh_client
  end

  test "operator loads resource usage and sees CPU and memory per container" do
    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: {
      "203.0.113.10" => docker_stats([
        stats(name: "track-planner-web-production-63cea7c46926aa7437725417bd51fb40b95cb80a", cpu: "0.42%", mem_usage: "128MiB", mem_limit: "1GiB"),
        stats(name: "track-planner-db", cpu: "0.05%", mem_usage: "64MiB", mem_limit: "512MiB")
      ])
    })

    get resource_usage_managed_app_url(managed_apps(:track_planner))

    assert_response :success
    assert_match "track-planner-db", response.body
    assert_match "0.42%", response.body
    assert_match "128MiB", response.body
    assert_match "203.0.113.10", response.body
  end

  test "the same container name on two servers gets a separate row per host" do
    managed_app = managed_app_with_containers("scaled_app", containers: [
      { "name" => "scaled_app-web-abc123", "kind" => "app", "state" => "running", "host" => "10.0.0.1" },
      { "name" => "scaled_app-web-abc123", "kind" => "app", "state" => "running", "host" => "10.0.0.2" }
    ])
    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: {
      "10.0.0.1" => docker_stats([ stats(name: "scaled_app-web-abc123", cpu: "0.10%") ]),
      "10.0.0.2" => docker_stats([ stats(name: "scaled_app-web-abc123", cpu: "0.20%") ])
    })

    get resource_usage_managed_app_url(managed_app)

    assert_response :success
    assert_match "10.0.0.1", response.body
    assert_match "10.0.0.2", response.body
    assert_match "0.10%", response.body
    assert_match "0.20%", response.body
  end

  test "resource usage for an unmanaged app is rejected" do
    get resource_usage_managed_app_url(managed_apps(:contractor_link))

    assert_response :not_found
  end

  test "an app with nothing running shows the empty message" do
    managed_app = managed_app_with_containers("idle_app", containers: [])

    get resource_usage_managed_app_url(managed_app)

    assert_response :success
    assert_match "No running containers to measure.", response.body
  end

  test "a container that yielded no metrics shows a 'no data' row" do
    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: {
      "203.0.113.10" => docker_stats([ stats(name: "track-planner-db") ])
    })

    get resource_usage_managed_app_url(managed_apps(:track_planner))

    assert_response :success
    assert_match "track-planner-web-production-63cea7c46926aa7437725417bd51fb40b95cb80a", response.body
    assert_match "no data (host unreachable?)", response.body
  end

  private

    def managed_app_with_containers(service_name, containers:)
      managed_app = ManagedApp.create!(repo_path: "/tmp/#{service_name}-#{SecureRandom.hex(4)}", service_name: service_name,
        status: :managed, discovered_at: Time.current, last_scanned_at: Time.current)
      destination = managed_app.app_destinations.create!(config_file: "deploy.yml", service_name: service_name,
        servers: { "web" => containers.map { |c| c["host"] }.uniq }, ssh_user: "deploy")
      DestinationStatus.create!(app_destination: destination, state: :down, checked_at: Time.current, containers: containers)
      managed_app
    end

    def stats(name:, cpu: "0.10%", mem_usage: "50MiB", mem_limit: "1GiB", mem_percent: "5.00%",
              net_io: "1kB / 1kB", block_io: "0B / 0B", pids: "1")
      { "Name" => name, "CPUPerc" => cpu, "MemUsage" => "#{mem_usage} / #{mem_limit}", "MemPerc" => mem_percent,
        "NetIO" => net_io, "BlockIO" => block_io, "PIDs" => pids }
    end

    def docker_stats(entries)
      entries.map(&:to_json).join("\n")
    end
end
