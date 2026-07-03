require "test_helper"

class Kamander::Kamal::StatusWriterTest < ActiveSupport::TestCase
  test "a report upserts one DestinationStatus for its destination" do
    destination = app_destinations(:contractor_link_base)
    report = build_report(destination, state: :running, containers: [ observed_container ])

    assert_difference -> { DestinationStatus.count }, 1 do
      Kamander::Kamal::StatusWriter.new([ report ]).call
    end

    status = destination.reload.destination_status
    assert_equal "running", status.state
    assert_equal 1, status.containers.size
    assert_equal "web", status.containers.first["label"]
    assert_equal "a1a1a1a", status.containers.first["version"]
  end

  test "re-writing overwrites the existing row in place instead of duplicating it" do
    destination = app_destinations(:track_planner_production)
    report = build_report(destination, state: :down, containers: [])

    assert_no_difference -> { DestinationStatus.count } do
      Kamander::Kamal::StatusWriter.new([ report ]).call
    end

    assert_equal "down", destination.reload.destination_status.state
  end

  test "an unreachable report stores the state and the SSH error, not stale containers" do
    destination = app_destinations(:track_planner_staging)
    report = build_report(destination, state: :unreachable, containers: [], error: "connection refused")

    Kamander::Kamal::StatusWriter.new([ report ]).call

    status = destination.reload.destination_status
    assert_equal "unreachable", status.state
    assert_equal "connection refused", status.error
    assert_empty status.containers
  end

  private

    def build_report(destination, state:, containers:, error: nil)
      Kamander::Kamal::DestinationReport.new(
        app_destination_id: destination.id,
        state: state,
        containers: containers,
        error: error,
        checked_at: Time.current
      )
    end

    def observed_container
      Kamander::Kamal::ObservedContainer.new(
        name: "contractor_link-web-a1a1a1a", kind: :app, label: "web", host: "3.14.15.92",
        state: :running, status_text: "Up 10 minutes", image: "contractor_link:latest", version: "a1a1a1a"
      )
    end
end
