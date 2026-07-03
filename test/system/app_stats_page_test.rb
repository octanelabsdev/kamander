require "application_system_test_case"

# Same live-broadcast proof as monitoring_status_test.rb, but for the show
# page's own stream ([managed_app, :statuses]) — a genuinely different
# broadcast target than the dashboard card's, so it needs its own coverage.
#
# Real commits required: Rails suppresses after_create_commit for records
# created inside the transactional-test wrapper (see monitoring_status_test.rb),
# so matrix_app is built with genuine commits and cleaned up in teardown.
class AppStatsPageTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  SHA = "1234567890abcdef1234567890abcdef12345678"
  STAGING_SHA = "abcdef1234567890abcdef1234567890abcdef12"

  setup do
    @original_ssh_client = Kamander::Kamal.ssh_client
    @original_perform_enqueued_jobs = ActiveJob::Base.queue_adapter.perform_enqueued_jobs
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = true
  end

  teardown do
    Kamander::Kamal.ssh_client = @original_ssh_client
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = @original_perform_enqueued_jobs
    ManagedApp.where(service_name: "matrix_app").destroy_all
  end

  test "operator opens an app's stats page and sees per-server container states, deployed version, and uptime" do
    app = build_managed_app("matrix_app", destinations: [
      { name: "production", servers: { "web" => [ "10.50.0.1", "10.50.0.2" ], "worker" => [ "10.50.0.1" ] },
        accessory_names: [ "db" ] },
      { name: "staging", servers: { "web" => [ "10.50.0.3" ] } }
    ])
    production = app.app_destinations.find_by!(name: "production")
    staging = app.app_destinations.find_by!(name: "staging")

    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: {
      "10.50.0.1" => docker_ps([
        container(name: "matrix_app-web-production-abc", state: "running", status: "Up 3 hours",
                  image: "kamander/matrix_app:#{SHA}", service: "matrix_app", role: "web", destination: "production"),
        container(name: "matrix_app-worker-production-abc", state: "running", status: "Up 10 minutes",
                  image: "kamander/matrix_app:#{SHA}", service: "matrix_app", role: "worker", destination: "production"),
        container(name: "matrix_app-db", state: "running", status: "Up 6 days", image: "postgres:16", service: "matrix_app-db"),
        container(name: "kamal-proxy", state: "running", status: "Up 6 days", image: "basecamp/kamal-proxy:latest", service: "kamal-proxy")
      ]),
      "10.50.0.2" => docker_ps([
        container(name: "matrix_app-web-production-abc", state: "running", status: "Up 45 minutes",
                  image: "kamander/matrix_app:#{SHA}", service: "matrix_app", role: "web", destination: "production")
      ]),
      "10.50.0.3" => docker_ps([
        container(name: "matrix_app-web-staging-abc", state: "running", status: "Up 20 minutes",
                  image: "kamander/matrix_app:#{STAGING_SHA}", service: "matrix_app", role: "web", destination: "staging")
      ])
    })

    using_session(:watcher) do
      visit managed_app_path(app)
      within("##{ActionView::RecordIdentifier.dom_id(production, :status)}") do
        assert_text "No status data yet — refresh to check."
      end
    end

    visit managed_app_path(app)
    click_on "Refresh"
    assert_text "Status refresh queued."

    using_session(:watcher) do
      within("##{ActionView::RecordIdentifier.dom_id(production, :status)}") do
        assert_text "Deployed:"
        assert_selector ".bg-emerald-500"

        # role x server matrix: 2 web rows (one per server) + 1 worker row
        assert_text "Up 3 hours"
        assert_text "Up 45 minutes"
        assert_text "Up 10 minutes"

        # SHA truncated to 12 chars on screen, full value in the title attribute
        sha_span = find("span.font-mono[title='#{SHA}']", match: :first)
        assert_equal SHA[0, 12], sha_span.text

        assert_text "db"
        assert_text "Up 6 days"
      end

      within("##{ActionView::RecordIdentifier.dom_id(staging, :status)}") do
        assert_text "Up 20 minutes"
      end
    end
  end

  private

    def build_managed_app(service_name, destinations:)
      managed_app = ManagedApp.create!(
        repo_path: "/tmp/#{service_name}-#{SecureRandom.hex(4)}",
        service_name: service_name,
        status: :managed,
        discovered_at: Time.current,
        last_scanned_at: Time.current
      )

      destinations.each do |attrs|
        managed_app.app_destinations.create!(
          name: attrs[:name],
          service_name: service_name,
          config_file: attrs[:name] ? "deploy.#{attrs[:name]}.yml" : "deploy.yml",
          servers: attrs[:servers],
          accessory_names: attrs.fetch(:accessory_names, []),
          ssh_user: "deploy"
        )
      end

      managed_app
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
end
