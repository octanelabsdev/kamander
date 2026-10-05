require "test_helper"

class StatusPollJobTest < ActiveJob::TestCase
  setup do
    @original_ssh_client = Kamander::Kamal.ssh_client
  end

  teardown do
    Kamander::Kamal.ssh_client = @original_ssh_client
  end

  test "operator changes trigger an enqueued status poll" do
    assert_enqueued_with(job: StatusPollJob) do
      StatusPollJob.perform_later
    end
  end

  test "the job limits concurrency to a single in-flight poll" do
    assert_equal "status_poll", StatusPollJob.concurrency_key
    assert_equal 1, StatusPollJob.concurrency_limit
  end

  test "a fleet poll writes rows for every managed destination" do
    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: {
      "203.0.113.10" => docker_ps([
        container(name: "track-planner-web-production-a1b2c3d", state: "running", status: "Up 1 hour"),
        container(name: "track-planner-db", state: "running", status: "Up 1 hour"),
        container(name: "track-planner-caddy", state: "running", status: "Up 1 hour"),
        container(name: "track-planner-domain-validator", state: "running", status: "Up 1 hour")
      ]),
      "203.0.113.11" => docker_ps([ container(name: "track-planner-web-staging-a1b2c3d", state: "running", status: "Up 1 hour") ])
    })

    StatusPollJob.perform_now

    assert_equal "running", app_destinations(:track_planner_production).reload.destination_status.state
    assert_equal "running", app_destinations(:track_planner_staging).reload.destination_status.state
  end

  test "a scoped poll writes only that app's destinations" do
    managed_apps(:contractor_link).update!(status: :managed)
    fake = FakeSshClient.new(responses: {
      "203.0.113.10" => docker_ps([ container(name: "track-planner-web-production-a1b2c3d", state: "running", status: "Up 1 hour") ]),
      "203.0.113.11" => docker_ps([ container(name: "track-planner-web-staging-a1b2c3d", state: "running", status: "Up 1 hour") ]),
      "3.14.15.92" => docker_ps([ container(name: "contractor_link-web-e5e6e7e", state: "running", status: "Up 1 hour") ])
    })
    Kamander::Kamal.ssh_client = fake

    StatusPollJob.perform_now(managed_app_id: managed_apps(:track_planner).id)

    assert app_destinations(:track_planner_production).reload.destination_status.present?
    assert app_destinations(:track_planner_staging).reload.destination_status.present?
    assert_nil app_destinations(:contractor_link_base).reload.destination_status
    assert_not_includes fake.calls.map(&:host), "3.14.15.92"
  end

  private

    def container(name:, state:, status:, image: "kamander/app:latest")
      { "Names" => name, "State" => state, "Status" => status, "Image" => image }
    end

    def docker_ps(containers)
      containers.map(&:to_json).join("\n")
    end
end
