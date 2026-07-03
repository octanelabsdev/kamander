require "application_system_test_case"

# Full pipeline proof: click Refresh, StatusPollJob runs (reader -> writer ->
# commit), and DestinationStatus's after_commit broadcast patches the
# dashboard live. Uses two Capybara sessions (same pattern as Basecamp's own
# messaging system tests) so the "watcher" session proves the broadcast
# reached the browser without ever reloading — a single session can't tell a
# live patch apart from the redirect's own fresh render, since both would
# show updated data either way.
#
# Real commits required: Rails suppresses after_create_commit for records
# created inside the transactional-test wrapper (proven directly — a brand
# new DestinationStatus never broadcasts there, fixture-backed updates do),
# so the dashboard apps here are built with genuine commits, and cleaned up
# in teardown since fixture reload alone doesn't run between assertions
# within a single test.
class MonitoringStatusTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  setup do
    @original_ssh_client = Kamander::Kamal.ssh_client
    @original_perform_enqueued_jobs = ActiveJob::Base.queue_adapter.perform_enqueued_jobs
    # Turbo submits "Refresh all" via fetch, not a native form post, so Selenium's
    # click doesn't block on the request the way it would for a real navigation —
    # wrapping just the click in ActiveJob::TestHelper#perform_enqueued_jobs risks
    # restoring the adapter before the job actually runs. Flipping this for the
    # whole test removes that race: whenever the request lands, the job runs
    # inline, and Capybara's own wait/retry absorbs the rest.
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = true
  end

  teardown do
    Kamander::Kamal.ssh_client = @original_ssh_client
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = @original_perform_enqueued_jobs
    ManagedApp.where(service_name: %w[running_app multi_app unreachable_app]).destroy_all
  end

  test "operator opens the dashboard and sees each managed app's live status appear" do
    running_app = build_managed_app("running_app",
      destinations: [ { name: nil, servers: { "web" => [ "10.40.0.1" ] } } ])

    multi_app = build_managed_app("multi_app", destinations: [
      { name: "production", servers: { "web" => [ "10.40.0.2" ] } },
      { name: "staging", servers: { "web" => [ "10.40.0.3" ], "worker" => [ "10.40.0.3" ] } }
    ])

    unreachable_app = build_managed_app("unreachable_app",
      destinations: [ { name: nil, servers: { "web" => [ "10.40.0.4" ] } } ])

    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: {
      "10.40.0.1" => docker_ps([ container(name: "running_app-web-abc123", state: "running", status: "Up 10 minutes",
                                            service: "running_app", role: "web", destination: "") ]),
      "10.40.0.2" => docker_ps([ container(name: "multi_app-web-production-abc123", state: "running", status: "Up 2 hours",
                                            service: "multi_app", role: "web", destination: "production") ]),
      "10.40.0.3" => docker_ps([
        container(name: "multi_app-web-staging-abc123", state: "running", status: "Up 1 hour",
                  service: "multi_app", role: "web", destination: "staging"),
        container(name: "multi_app-worker-staging-abc123", state: "exited", status: "Exited (0) 5 minutes ago",
                  service: "multi_app", role: "worker", destination: "staging")
      ]),
      "10.40.0.4" => :unreachable
    })

    using_session(:watcher) do
      visit root_path
      within("##{ActionView::RecordIdentifier.dom_id(running_app)}") { assert_text "not yet checked" }
      within("##{ActionView::RecordIdentifier.dom_id(multi_app)}") { assert_text "not yet checked" }
      within("##{ActionView::RecordIdentifier.dom_id(unreachable_app)}") { assert_text "not yet checked" }
    end

    visit root_path
    click_on "Refresh all"
    assert_text "Status refresh queued."

    using_session(:watcher) do
      within("##{ActionView::RecordIdentifier.dom_id(running_app)}") do
        assert_no_text "not yet checked"
        assert_text "as of"
        assert_selector "span[title='Running']"
        assert_text "web ✓"
      end

      within("##{ActionView::RecordIdentifier.dom_id(multi_app)}") do
        assert_text "as of"
        assert_selector "span[title='Partial']"
        assert_text "1/2 up"
      end

      within("##{ActionView::RecordIdentifier.dom_id(unreachable_app)}") do
        assert_no_text "not yet checked"
        assert_text "as of"
        assert_selector "span[title='Unreachable']"
        assert_selector "[title='connection unreachable']"
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
