require "test_helper"

class Kamander::Kamal::LifecycleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "restart docker-restarts every running app container over ssh, grouped by host" do
    destination = destination_with_status(containers: [
      container(name: "lifecycle_app-web-abc123", kind: "app", state: "running", host: "10.0.0.1"),
      container(name: "lifecycle_app-worker-abc123", kind: "app", state: "running", host: "10.0.0.2")
    ])
    operation = queued_operation(destination, verb: :restart)
    ssh = FakeSshClient.new

    call_lifecycle(operation, ssh_client: ssh)

    operation.reload
    assert operation.succeeded?
    assert_equal %w[10.0.0.1 10.0.0.2], ssh.calls.map(&:host).sort
    assert ssh.calls.all? { |call| call.command.start_with?("docker restart") }
  end

  test "restart fails with a clear message when nothing is running" do
    destination = destination_with_status(containers: [
      container(name: "lifecycle_app-web-abc123", kind: "app", state: "exited", host: "10.0.0.1")
    ])
    operation = queued_operation(destination, verb: :restart)
    ssh = FakeSshClient.new

    call_lifecycle(operation, ssh_client: ssh)

    operation.reload
    assert operation.failed?
    assert_match(/nothing running to restart/, operation.output)
    assert_empty ssh.calls
  end

  test "reboot boots the pinned version via the repo's own bin/kamal, running in the repo's directory" do
    destination = destination_with_status(containers: [
      container(name: "lifecycle_app-web-production-abc123", kind: "app", state: "running", host: "10.0.0.1", version: "abc123")
    ])
    operation = queued_operation(destination, verb: :reboot)
    argv = [ "bin/kamal", "app", "boot", "-d", "production", "--version", "abc123" ]
    runner = FakeCommandRunner.new(responses: { argv => { lines: [ "Booting..." ], exit_status: 0 } })

    call_lifecycle(operation, command_runner: runner)

    operation.reload
    assert operation.succeeded?
    assert_equal argv.join(" "), operation.command
    assert_equal "Booting...\n", operation.output
    call = runner.calls.first
    assert_equal argv, call.command
    assert_equal destination.managed_app.repo_path, call.chdir
  end

  test "start is blocked without a known deployed version" do
    destination = destination_with_status(containers: [])
    operation = queued_operation(destination, verb: :start)
    runner = FakeCommandRunner.new

    call_lifecycle(operation, command_runner: runner)

    operation.reload
    assert operation.failed?
    assert_match(/no known deployed version/, operation.output)
    assert_empty runner.calls
  end

  test "stop passes -d for a destination, omits it for the base app" do
    destination = destination_with_status(name: nil, containers: [])
    operation = queued_operation(destination, verb: :stop)
    argv = [ "bin/kamal", "app", "stop" ]
    runner = FakeCommandRunner.new(responses: { argv => { lines: [ "Stopping..." ], exit_status: 0 } })

    call_lifecycle(operation, command_runner: runner)

    assert operation.reload.succeeded?
    assert_equal argv, runner.calls.first.command
  end

  test "streamed lines append to operation.output as they arrive" do
    destination = destination_with_status(containers: [])
    operation = queued_operation(destination, verb: :stop)
    argv = [ "bin/kamal", "app", "stop", "-d", "production" ]
    runner = FakeCommandRunner.new(responses: { argv => { lines: [ "Stopping web...", "Stopped." ], exit_status: 0 } })

    call_lifecycle(operation, command_runner: runner)

    assert_equal "Stopping web...\nStopped.\n", operation.reload.output
  end

  test "a failed kamal command marks the operation failed with its exit status" do
    destination = destination_with_status(containers: [])
    operation = queued_operation(destination, verb: :stop)
    argv = [ "bin/kamal", "app", "stop", "-d", "production" ]
    runner = FakeCommandRunner.new(responses: { argv => { lines: [ "ERROR: could not connect" ], exit_status: 1 } })

    call_lifecycle(operation, command_runner: runner)

    operation.reload
    assert operation.failed?
    assert_equal 1, operation.exit_status
    assert_equal "ERROR: could not connect\n", operation.output
  end

  test "a missing bin/kamal binstub fails the operation with guidance, not a raise" do
    destination = destination_with_status(containers: [])
    operation = queued_operation(destination, verb: :stop)
    argv = [ "bin/kamal", "app", "stop", "-d", "production" ]
    runner = FakeCommandRunner.new(responses: {
      argv => { lines: [ "kamander: No such file or directory - bin/kamal" ], exit_status: nil }
    })

    call_lifecycle(operation, command_runner: runner)

    operation.reload
    assert operation.failed?
    assert_nil operation.exit_status
    assert_match(/No such file or directory/, operation.output)
  end

  test "a finished operation chains a scoped status poll" do
    destination = destination_with_status(containers: [])
    operation = queued_operation(destination, verb: :stop)

    assert_enqueued_with(job: StatusPollJob, args: [ { managed_app_id: destination.managed_app_id } ]) do
      call_lifecycle(operation, command_runner: FakeCommandRunner.new)
    end
  end

  private

    def managed_app_with_destination(name:)
      managed_app = ManagedApp.create!(repo_path: "/tmp/lifecycle_app-#{name}-#{SecureRandom.hex(4)}", service_name: "lifecycle_app",
        status: :managed, discovered_at: Time.current, last_scanned_at: Time.current)
      managed_app.app_destinations.create!(name: name, service_name: "lifecycle_app",
        config_file: name ? "deploy.#{name}.yml" : "deploy.yml", servers: { "web" => [ "10.0.0.1" ] }, ssh_user: "deploy")
    end

    def destination_with_status(containers:, name: "production", state: "running")
      destination = managed_app_with_destination(name: name)
      DestinationStatus.create!(app_destination: destination, state: state, containers: containers, checked_at: Time.current)
      destination
    end

    def container(name:, kind:, state:, host:, version: nil)
      { "name" => name, "kind" => kind, "state" => state, "host" => host, "version" => version,
        "service" => "lifecycle_app", "role" => kind == "app" ? "web" : nil, "destination" => nil,
        "status_text" => nil, "image" => nil }
    end

    def queued_operation(destination, verb:)
      Operation.create!(managed_app: destination.managed_app, app_destination: destination, verb: verb,
        status: :queued, command: "pending")
    end

    def call_lifecycle(operation, command_runner: FakeCommandRunner.new, ssh_client: FakeSshClient.new)
      Kamander::Kamal::Lifecycle.new(operation: operation, command_runner: command_runner, ssh_client: ssh_client).call
    end
end
