require "application_system_test_case"

# MetricsReader runs synchronously inside the controller action (design §4 —
# on-demand, never a job), so there's no execution-timing decision to make
# here: click the frame link, let Capybara wait for the response to render.
class ResourceUsageTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  setup do
    @original_ssh_client = Kamander::Kamal.ssh_client
  end

  teardown do
    Kamander::Kamal.ssh_client = @original_ssh_client
    ManagedApp.where(service_name: "metrics_app").destroy_all
  end

  test "operator loads resource usage on the stats page and sees CPU and memory per container" do
    destination = build_destination
    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: {
      "10.80.0.1" => docker_stats([
        stats(name: "metrics_app-web-abc123", cpu: "0.42%", mem_usage: "128MiB", mem_limit: "1GiB", mem_percent: "12.50%")
      ])
    })

    visit managed_app_path(destination.managed_app)
    click_on "Load resource usage"

    within("turbo-frame#resource_usage") do
      assert_text "metrics_app-web-abc123"
      assert_text "10.80.0.1"
      assert_text "0.42%"
      assert_text "128MiB / 1GiB (12.50%)"
    end
  end

  private

    def build_destination
      managed_app = ManagedApp.create!(repo_path: "/tmp/metrics_app-#{SecureRandom.hex(4)}", service_name: "metrics_app",
        status: :managed, discovered_at: Time.current, last_scanned_at: Time.current)
      destination = managed_app.app_destinations.create!(config_file: "deploy.yml", service_name: "metrics_app",
        servers: { "web" => [ "10.80.0.1" ] }, ssh_user: "deploy")
      DestinationStatus.create!(app_destination: destination, state: :running, checked_at: Time.current, containers: [
        { "name" => "metrics_app-web-abc123", "kind" => "app", "state" => "running", "host" => "10.80.0.1",
          "version" => "abc123", "service" => "metrics_app", "role" => "web", "destination" => nil,
          "status_text" => "Up 1 hour", "image" => nil }
      ])
      destination
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
