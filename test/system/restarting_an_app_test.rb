require "application_system_test_case"

# Job execution is decoupled from the click on purpose: the operator lands on
# the console via redirect BEFORE the operation has run (queued, no output
# yet), then LifecycleJob is run explicitly from here — same process, same
# pinned connection as the browser thread, so Lifecycle's broadcasts (called
# eagerly on each line/badge update, not via after_commit) patch the
# still-open console page live. A single session proves that honestly: no
# navigation happens between "queued" and "Succeeded", so anything that
# appears did so via the broadcast, not a reload.
class RestartingAnAppTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  setup do
    @original_ssh_client = Kamander::Kamal.ssh_client
    @original_command_runner = Kamander::Kamal.command_runner
  end

  teardown do
    Kamander::Kamal.ssh_client = @original_ssh_client
    Kamander::Kamal.command_runner = @original_command_runner
    ManagedApp.where(service_name: "restart_app").destroy_all
  end

  test "operator clicks Restart on a destination, watches the log stream, and sees the status refresh" do
    destination = build_destination

    # Wired for both calls Lifecycle's chain makes: the restart itself (SSH)
    # and the follow-up StatusPollJob's docker ps (also SSH) — FakeCommandRunner
    # is wired too even though restart never touches it, per the task's ask.
    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: {
      "10.60.0.1" => docker_ps([ raw_container(name: "restart_app-web-staging-abc123", state: "running", status: "Up 1 hour",
                                                service: "restart_app", role: "web", destination: "staging") ])
    })
    Kamander::Kamal.command_runner = FakeCommandRunner.new

    visit managed_app_path(destination.managed_app)
    click_on "Restart"

    assert_text "queued…"
    assert_no_text "Succeeded"

    operation = Operation.last
    LifecycleJob.perform_now(operation)
    StatusPollJob.perform_now(managed_app_id: destination.managed_app_id)

    assert_text "docker restart restart_app-web-staging-abc123"
    assert_text "10.60.0.1:"
    assert_text "Succeeded"

    visit managed_app_path(destination.managed_app)
    assert_no_text "Operation in progress"
    assert_button "Restart"
  end

  private

    def build_destination
      managed_app = ManagedApp.create!(repo_path: "/tmp/restart_app-#{SecureRandom.hex(4)}", service_name: "restart_app",
        status: :managed, discovered_at: Time.current, last_scanned_at: Time.current)
      destination = managed_app.app_destinations.create!(name: "staging", service_name: "restart_app",
        config_file: "deploy.staging.yml", servers: { "web" => [ "10.60.0.1" ] }, ssh_user: "deploy")
      DestinationStatus.create!(app_destination: destination, state: :running, checked_at: Time.current,
        containers: [ seeded_container(name: "restart_app-web-staging-abc123", host: "10.60.0.1", version: "abc123") ])
      destination
    end

    # Shape DestinationStatus.containers is cached in — what Lifecycle reads
    # directly (no re-parsing) to build the restart command.
    def seeded_container(name:, host:, version:)
      { "name" => name, "kind" => "app", "state" => "running", "host" => host, "version" => version,
        "service" => "restart_app", "role" => "web", "destination" => "staging", "status_text" => "Up 1 hour", "image" => nil }
    end

    # Raw `docker ps --format {{json .}}` shape FakeSshClient hands back — what
    # the chained StatusPollJob's StatusReader parses on re-poll.
    def raw_container(name:, state:, status:, service:, role:, destination:, image: "kamander/app:latest")
      { "Names" => name, "State" => state, "Status" => status, "Image" => image,
        "Labels" => [ "service=#{service}", "role=#{role}", "destination=#{destination}" ].join(",") }
    end

    def docker_ps(containers)
      containers.map(&:to_json).join("\n")
    end
end
