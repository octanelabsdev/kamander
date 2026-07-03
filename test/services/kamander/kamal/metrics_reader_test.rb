require "test_helper"

class Kamander::Kamal::MetricsReaderTest < ActiveSupport::TestCase
  test "loading metrics for an app queries each of its hosts once with only that app's containers" do
    app_a = managed_app_with_containers("app_a", containers: [
      container(name: "app_a-web-abc123", host: "10.0.0.1"),
      container(name: "app_a-db", kind: "accessory", host: "10.0.0.1")
    ])
    managed_app_with_containers("app_b", containers: [ container(name: "app_b-web-def456", host: "10.0.0.1") ])
    fake = FakeSshClient.new(responses: {
      "10.0.0.1" => docker_stats([ stats(name: "app_a-web-abc123"), stats(name: "app_a-db") ])
    })

    Kamander::Kamal::MetricsReader.new(managed_app: app_a, ssh_client: fake).call

    assert_equal 1, fake.calls.size
    command = fake.calls.first.command
    assert_includes command, "app_a-web-abc123"
    assert_includes command, "app_a-db"
    assert_not_includes command, "app_b-web-def456"
  end

  test "metrics parse cpu and memory for each container" do
    app = managed_app_with_containers("web_app", containers: [ container(name: "web_app-web-abc123", host: "10.0.0.2") ])
    fake = FakeSshClient.new(responses: {
      "10.0.0.2" => docker_stats([ stats(name: "web_app-web-abc123", cpu: "0.15%", mem_usage: "190MiB", mem_limit: "3.83GiB",
                                          mem_percent: "4.95%", net_io: "1.2kB / 648B", block_io: "0B / 0B", pids: "3") ])
    })

    metrics = Kamander::Kamal::MetricsReader.new(managed_app: app, ssh_client: fake).call

    container_metrics = metrics.sole
    assert_equal "web_app-web-abc123", container_metrics.name
    assert_equal "10.0.0.2", container_metrics.host
    assert_equal "0.15%", container_metrics.cpu_percent
    assert_equal "190MiB", container_metrics.mem_usage
    assert_equal "3.83GiB", container_metrics.mem_limit
    assert_equal "4.95%", container_metrics.mem_percent
    assert_equal "1.2kB / 648B", container_metrics.net_io
    assert_equal "0B / 0B", container_metrics.block_io
    assert_equal "3", container_metrics.pids
  end

  test "a role running on two servers reports metrics for each host separately" do
    app = managed_app_with_containers("replicated_app", containers: [
      container(name: "replicated_app-web-abc123", host: "10.0.0.6"),
      container(name: "replicated_app-web-abc123", host: "10.0.0.7")
    ])
    fake = FakeSshClient.new(responses: {
      "10.0.0.6" => docker_stats([ stats(name: "replicated_app-web-abc123", cpu: "0.20%") ]),
      "10.0.0.7" => docker_stats([ stats(name: "replicated_app-web-abc123", cpu: "0.45%") ])
    })

    metrics = Kamander::Kamal::MetricsReader.new(managed_app: app, ssh_client: fake).call

    assert_equal 2, metrics.size
    by_host = metrics.index_by(&:host)
    assert_equal "0.20%", by_host.fetch("10.0.0.6").cpu_percent
    assert_equal "0.45%", by_host.fetch("10.0.0.7").cpu_percent
  end

  test "an unreachable host yields no metrics for its containers without failing the rest" do
    app = managed_app_with_containers("split_app",
      containers: [ container(name: "split_app-web-abc123", host: "10.0.0.3"), container(name: "split_app-worker-abc123", host: "10.0.0.4") ])
    fake = FakeSshClient.new(responses: {
      "10.0.0.3" => docker_stats([ stats(name: "split_app-web-abc123") ]),
      "10.0.0.4" => :unreachable
    })

    metrics = Kamander::Kamal::MetricsReader.new(managed_app: app, ssh_client: fake).call

    assert_equal [ "split_app-web-abc123" ], metrics.map(&:name)
  end

  test ".expected_containers returns the running app/accessory (name, host) slots this reader will look up" do
    app = managed_app_with_containers("expected_app", containers: [
      container(name: "expected_app-web-abc123", host: "10.0.0.8"),
      container(name: "expected_app-worker-abc123", host: "10.0.0.8", state: "exited"),
      container(name: "kamal-proxy", kind: "proxy", host: "10.0.0.8")
    ])

    expected = Kamander::Kamal::MetricsReader.expected_containers(app)

    assert_equal [ { name: "expected_app-web-abc123", host: "10.0.0.8" } ], expected
  end

  test "an app with nothing running yields no metrics" do
    app = managed_app_with_containers("idle_app",
      containers: [ container(name: "idle_app-web-abc123", host: "10.0.0.5", state: "exited") ])
    fake = FakeSshClient.new

    metrics = Kamander::Kamal::MetricsReader.new(managed_app: app, ssh_client: fake).call

    assert_empty metrics
    assert_empty fake.calls
  end

  private

    def managed_app_with_containers(service_name, containers:)
      managed_app = ManagedApp.create!(repo_path: "/tmp/#{service_name}-#{SecureRandom.hex(4)}", service_name: service_name,
        status: :managed, discovered_at: Time.current, last_scanned_at: Time.current)
      destination = managed_app.app_destinations.create!(config_file: "deploy.yml", service_name: service_name,
        servers: { "web" => containers.map { |c| c["host"] }.uniq }, ssh_user: "deploy")
      DestinationStatus.create!(app_destination: destination, state: :running, checked_at: Time.current, containers: containers)
      managed_app
    end

    def container(name:, host:, kind: "app", state: "running")
      { "name" => name, "kind" => kind, "state" => state, "host" => host, "service" => nil, "role" => nil,
        "destination" => nil, "status_text" => nil, "image" => nil, "version" => nil }
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
