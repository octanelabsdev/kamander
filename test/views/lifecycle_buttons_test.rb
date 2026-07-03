require "test_helper"

# Renders _lifecycle_buttons directly against a range of destination states
# and names to lock down the safety matrix: which verbs appear per state, and
# which of those carry a confirmation (plain turbo_confirm vs the typed modal).
class LifecycleButtonsTest < ActionView::TestCase
  tests LifecycleButtonsHelper

  test "operator sees Restart, Reboot, and Stop when a destination is running" do
    destination = build_destination(name: "staging", state: "running")

    render_buttons(destination)

    assert_button "Restart"
    assert_button "Reboot"
    assert_button "Stop"
  end

  test "operator sees Restart, Reboot, and Stop when a destination is partially up" do
    destination = build_destination(name: "staging", state: "partial")

    render_buttons(destination)

    assert_button "Restart"
    assert_button "Reboot"
    assert_button "Stop"
  end

  test "operator sees only Start when a destination is down" do
    destination = build_destination(name: "staging", state: "down")

    render_buttons(destination)

    assert_button "Start"
    assert_no_button "Restart"
    assert_no_button "Reboot"
    assert_no_button "Stop"
  end

  test "operator sees a hint instead of buttons when a destination has never been checked" do
    destination = build_destination(name: "staging", state: nil)

    render_buttons(destination)

    assert_select "span", text: "Refresh status first"
    assert_no_button "Restart"
  end

  test "operator sees a hint instead of buttons when a destination is unreachable" do
    destination = build_destination(name: "staging", state: "unreachable")

    render_buttons(destination)

    assert_select "span", text: "Refresh status first"
    assert_no_button "Restart"
  end

  test "operator sees a hint instead of buttons when a destination's state is explicitly unknown" do
    destination = build_destination(name: "staging", state: "unknown")

    render_buttons(destination)

    assert_select "span", text: "Refresh status first"
    assert_no_button "Restart"
  end

  test "operator sees an in-progress link instead of buttons when an operation is already running" do
    destination = build_destination(name: "staging", state: "running")
    operation = Operation.create!(managed_app: destination.managed_app, app_destination: destination,
      verb: :restart, status: :running, command: "docker restart widgetco-web-staging-abc123")

    render_buttons(destination)

    assert_select "a[href='#{operation_path(operation)}']", text: /Operation in progress/
    assert_no_button "Restart"
  end

  test "stopping a non-production destination requires a plain confirmation" do
    destination = build_destination(name: "staging", state: "running")

    render_buttons(destination)

    assert_confirm "Stop", present: true
  end

  test "restarting a non-production destination requires no confirmation" do
    destination = build_destination(name: "staging", state: "running")

    render_buttons(destination)

    assert_confirm "Restart", present: false
  end

  test "restarting and rebooting a production destination require confirmation" do
    destination = build_destination(name: "production", state: "running")

    render_buttons(destination)

    assert_confirm "Restart", present: true
    assert_confirm "Reboot", present: true
  end

  test "stopping a production destination has no plain confirm and opens the typed modal instead" do
    destination = build_destination(name: "production", state: "running")

    render_buttons(destination)

    assert_select "button[data-action='confirm-stop#open']", text: "Stop"
    assert_confirm "Stop", present: false
    assert_typed_modal(destination)
  end

  test "the prod short form is treated as production too" do
    destination = build_destination(name: "prod", state: "running")

    render_buttons(destination)

    assert_confirm "Restart", present: true
    assert_typed_modal(destination)
  end

  test "a base destination's Stop opens the typed modal, same as a named production destination" do
    destination = build_destination(name: nil, state: "running")

    render_buttons(destination)

    assert_confirm "Stop", present: false
    assert_typed_modal(destination)
  end

  test "a base destination's Restart and Reboot require confirmation" do
    destination = build_destination(name: nil, state: "running")

    render_buttons(destination)

    assert_confirm "Restart", present: true
    assert_confirm "Reboot", present: true
  end

  private

    def build_destination(name:, state:, service_name: "widgetco")
      managed_app = ManagedApp.create!(
        repo_path: "/tmp/#{service_name}-#{name}-#{SecureRandom.hex(4)}",
        service_name: service_name, status: :managed,
        discovered_at: Time.current, last_scanned_at: Time.current
      )

      destination = managed_app.app_destinations.create!(
        name: name, service_name: service_name,
        config_file: name ? "deploy.#{name}.yml" : "deploy.yml",
        servers: { "web" => [ "10.20.0.1" ] }
      )

      destination.create_destination_status!(state: state, checked_at: Time.current, containers: []) if state

      destination
    end

    def render_buttons(destination)
      # Reload: creating destination_status earlier in the same object's lifetime
      # can leave its has_one active_operation association cache stale from
      # before the operation existed — a same-process test artifact, not
      # something that happens in the app (each request loads its own records).
      render partial: "managed_apps/lifecycle_buttons", locals: { destination: destination.reload }
    end

    def assert_button(label)
      assert_select "button", text: label
    end

    def assert_no_button(label)
      assert_select "button", text: label, count: 0
    end

    def assert_confirm(label, present:)
      assert_select "button", text: label do |elements|
        attribute = elements.first["data-turbo-confirm"]
        present ? assert(attribute.present?, "expected #{label} to carry a turbo_confirm") :
          assert_nil(attribute, "expected #{label} to have no turbo_confirm")
      end
    end

    def assert_typed_modal(destination)
      assert_select "div[data-controller='confirm-stop'][data-confirm-stop-service-name-value='#{destination.managed_app.display_label}']"
      assert_select "button[data-confirm-stop-target='submit'][disabled]", text: "Confirm stop"
    end
end
