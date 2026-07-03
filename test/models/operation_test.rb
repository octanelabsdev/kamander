require "test_helper"

class OperationTest < ActiveSupport::TestCase
  test "verb enum covers restart, reboot, stop, and start" do
    operation = operations(:track_planner_production_restart_succeeded)
    assert operation.restart?

    operation.verb = :reboot
    assert operation.reboot?
  end

  test "status enum covers queued, running, succeeded, and failed" do
    operation = operations(:track_planner_staging_stop_failed)
    assert operation.failed?

    operation.status = :running
    assert operation.running?
  end

  test "duration is present once an operation has finished" do
    operation = operations(:track_planner_production_restart_succeeded)
    assert_in_delta 60, operation.duration, 1
  end

  test "duration is nil while an operation is still running" do
    operation = operations(:track_planner_production_restart_succeeded)
    operation.finished_at = nil
    assert_nil operation.duration
  end

  test "an operation rejects a destination belonging to a different app" do
    operation = Operation.new(managed_app: managed_apps(:contractor_link), app_destination: app_destinations(:track_planner_production),
                               verb: :restart, command: "docker restart track-planner-web-production", status: :queued)

    assert_not operation.valid?
    assert_includes operation.errors[:app_destination], "must belong to the operation's managed app"
  end

  test "active scope returns only queued and running operations" do
    destination = app_destinations(:contractor_link_base)
    active_op = Operation.create!(managed_app: managed_apps(:contractor_link), app_destination: destination,
                                   verb: :restart, command: "docker restart contractor_link-web", status: :queued)

    assert_includes Operation.active, active_op
    assert_not_includes Operation.active, operations(:track_planner_production_restart_succeeded)
  end

  test "the partial unique index still targets queued and running by their raw enum values" do
    assert_equal [ 0, 1 ], Operation.statuses.values_at("queued", "running")
  end

  # THE LOCK: the design assigns the friendly pre-check to the controller
  # (P3-E, not yet built) and treats the partial unique index as the race
  # backstop — so there's no model-level uniqueness validation here on
  # purpose. This test proves the raw DB constraint holds on its own.
  test "a destination can only have one active operation at a time" do
    destination = app_destinations(:contractor_link_base)
    Operation.create!(managed_app: managed_apps(:contractor_link), app_destination: destination,
                       verb: :restart, command: "docker restart contractor_link-web", status: :queued)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Operation.create!(managed_app: managed_apps(:contractor_link), app_destination: destination,
                         verb: :stop, command: "bin/kamal app stop", status: :running)
    end
  end

  test "a terminal operation frees the destination for the next one" do
    destination = app_destinations(:track_planner_production)

    next_operation = Operation.create!(managed_app: managed_apps(:track_planner), app_destination: destination,
                                        verb: :restart, command: "docker restart track-planner-web-production", status: :queued)

    assert next_operation.persisted?
    assert_equal 2, destination.operations.count
  end
end
