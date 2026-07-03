require "test_helper"

class LifecycleJobTest < ActiveJob::TestCase
  setup do
    @original_command_runner = Kamander::Kamal.command_runner
    @original_ssh_client = Kamander::Kamal.ssh_client
  end

  teardown do
    Kamander::Kamal.command_runner = @original_command_runner
    Kamander::Kamal.ssh_client = @original_ssh_client
  end

  test "an operation enqueues a lifecycle job" do
    operation = queued_operation(verb: :stop)

    assert_enqueued_with(job: LifecycleJob, args: [ operation ]) do
      LifecycleJob.perform_later(operation)
    end
  end

  test "the job runs on its own lifecycle queue, not the fleet poll's" do
    assert_equal "lifecycle", LifecycleJob.queue_name
  end

  test "performing the job runs the lifecycle for its operation" do
    operation = queued_operation(verb: :stop)
    argv = [ "bin/kamal", "app", "stop" ]
    Kamander::Kamal.command_runner = FakeCommandRunner.new(responses: { argv => { lines: [ "Stopping..." ], exit_status: 0 } })

    LifecycleJob.perform_now(operation)

    operation.reload
    assert operation.succeeded?
    assert_equal "Stopping...\n", operation.output
  end

  test "a crash inside the job marks the operation failed instead of leaving it running" do
    operation = queued_operation(verb: :stop)
    Kamander::Kamal.command_runner = RaisingCommandRunner.new

    LifecycleJob.perform_now(operation)

    operation.reload
    assert operation.failed?
    assert_match(/lifecycle blew up/, operation.output)
    assert_nil operation.app_destination.reload.active_operation
  end

  test "a crash mid-stream preserves the lines already streamed before the failure" do
    operation = queued_operation(verb: :stop)
    Kamander::Kamal.command_runner = RaisingCommandRunner.new(lines: [ "Stopping web...", "Stopping worker..." ])

    LifecycleJob.perform_now(operation)

    operation.reload
    assert operation.failed?
    assert_equal "Stopping web...\nStopping worker...\nkamander: lifecycle blew up\n", operation.output
  end

  private

    class RaisingCommandRunner
      def initialize(lines: [])
        @lines = lines
      end

      def stream(...)
        @lines.each { |line| yield line }
        raise "lifecycle blew up"
      end
    end

    def queued_operation(verb:)
      managed_app = ManagedApp.create!(repo_path: "/tmp/lifecycle_job_app-#{SecureRandom.hex(4)}", service_name: "lifecycle_job_app",
        status: :managed, discovered_at: Time.current, last_scanned_at: Time.current)
      destination = managed_app.app_destinations.create!(config_file: "deploy.yml", service_name: "lifecycle_job_app",
        servers: { "web" => [ "10.0.0.1" ] }, ssh_user: "deploy")
      Operation.create!(managed_app: managed_app, app_destination: destination, verb: verb, status: :queued, command: "pending")
    end
end
