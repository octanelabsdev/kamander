require "application_system_test_case"

class StoppingProductionTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  setup do
    @original_command_runner = Kamander::Kamal.command_runner
  end

  teardown do
    Kamander::Kamal.command_runner = @original_command_runner
    ManagedApp.where(service_name: "stop_app").destroy_all
  end

  test "operator stops a production destination only after typing the service name to confirm" do
    destination = build_destination
    argv = [ "bin/kamal", "app", "stop", "-d", "production" ]
    Kamander::Kamal.command_runner = FakeCommandRunner.new(responses: {
      argv => { lines: [ "Stopping web...", "Stopped." ], exit_status: 0 }
    })

    visit managed_app_path(destination.managed_app)

    # No accept_confirm anywhere below — proving the typed modal replaced the
    # plain turbo_confirm entirely for a production Stop (design §5.2), not
    # just sitting alongside it.
    click_on "Stop"
    assert_selector "[data-confirm-stop-target='dialog']"
    assert_selector "[data-confirm-stop-target='submit'][disabled]"

    input = find("[data-confirm-stop-target='input']")
    input.set("definitely-wrong-name")
    assert_selector "[data-confirm-stop-target='submit'][disabled]"

    input.set(destination.managed_app.display_label)
    assert_no_selector "[data-confirm-stop-target='submit'][disabled]"

    click_on "Confirm stop"

    assert_text "queued…"

    LifecycleJob.perform_now(Operation.last)

    assert_text "bin/kamal app stop -d production"
    assert_text "Stopping web..."
    assert_text "Stopped."
    assert_text "Succeeded"
  end

  private

    def build_destination
      managed_app = ManagedApp.create!(repo_path: "/tmp/stop_app-#{SecureRandom.hex(4)}", service_name: "stop_app",
        status: :managed, discovered_at: Time.current, last_scanned_at: Time.current)
      destination = managed_app.app_destinations.create!(name: "production", service_name: "stop_app",
        config_file: "deploy.production.yml", servers: { "web" => [ "10.70.0.1" ] }, ssh_user: "deploy")
      DestinationStatus.create!(app_destination: destination, state: :running, checked_at: Time.current, containers: [
        { "name" => "stop_app-web-production-abc123", "kind" => "app", "state" => "running", "host" => "10.70.0.1",
          "version" => "abc123", "service" => "stop_app", "role" => "web", "destination" => "production",
          "status_text" => "Up 1 hour", "image" => nil }
      ])
      destination
    end
end
