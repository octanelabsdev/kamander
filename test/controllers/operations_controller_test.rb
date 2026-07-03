require "test_helper"

class OperationsControllerTest < ActionDispatch::IntegrationTest
  test "operator triggers a restart and an operation is queued with a job enqueued" do
    destination = app_destinations(:track_planner_production)

    assert_enqueued_with(job: LifecycleJob) do
      assert_difference "Operation.count", 1 do
        post operations_url, params: { verb: "restart", app_destination_id: destination.id }
      end
    end

    operation = Operation.last
    assert_redirected_to operation_path(operation)
    assert operation.queued?
    assert_equal "restart", operation.verb
  end

  test "a second operation on a busy destination is rejected with a friendly message" do
    destination = app_destinations(:track_planner_production)
    Operation.create!(managed_app: destination.managed_app, app_destination: destination,
      verb: :restart, status: :queued, command: "pending")

    assert_no_difference "Operation.count" do
      assert_no_enqueued_jobs(only: LifecycleJob) do
        post operations_url, params: { verb: "stop", app_destination_id: destination.id }
      end
    end

    assert_redirected_to root_path
    assert_match(/already running/, flash[:alert])
  end

  test "the race between two simultaneous operations degrades to the friendly busy message" do
    destination = app_destinations(:track_planner_production)
    Operation.create!(managed_app: destination.managed_app, app_destination: destination,
      verb: :restart, status: :queued, command: "pending")

    # Simulates two requests landing back to back: active_operation reads nil,
    # as if the pre-check ran a beat before the conflicting insert landed — so
    # it's the RecordNotUnique rescue around save!, not the pre-check, that has
    # to catch the real partial-unique-index conflict here.
    with_active_operation_stubbed_to_nil do
      assert_no_difference "Operation.count" do
        assert_no_enqueued_jobs(only: LifecycleJob) do
          post operations_url, params: { verb: "stop", app_destination_id: destination.id }
        end
      end
    end

    assert_redirected_to root_path
    assert_match(/already running/, flash[:alert])
  end

  test "an operation on an unmanaged app's destination is rejected" do
    destination = app_destinations(:contractor_link_base)

    post operations_url, params: { verb: "restart", app_destination_id: destination.id }

    assert_response :not_found
  end

  test "an invalid verb is rejected" do
    destination = app_destinations(:track_planner_production)

    assert_no_difference "Operation.count" do
      post operations_url, params: { verb: "deploy", app_destination_id: destination.id }
    end

    assert_redirected_to root_path
    assert_match(/Unknown operation/, flash[:alert])
  end

  test "show renders the console with command, status, and output" do
    operation = operations(:track_planner_production_restart_succeeded)

    get operation_url(operation)

    assert_response :success
    assert_match operation.command, response.body
    assert_match "Succeeded", response.body
    assert_match "exit 0", response.body
    assert_match "Restarting container", response.body
  end

  private

    # No mocking gem in this project — plain-Ruby method swap, restored via
    # the captured UnboundMethod so no other test sees the stub.
    def with_active_operation_stubbed_to_nil
      original = AppDestination.instance_method(:active_operation)
      AppDestination.define_method(:active_operation) { nil }
      yield
    ensure
      AppDestination.define_method(:active_operation, original)
    end
end
