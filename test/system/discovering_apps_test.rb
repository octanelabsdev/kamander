require "application_system_test_case"

class DiscoveringAppsTest < ApplicationSystemTestCase
  setup do
    Setting.current.update!(scan_root: file_fixture("repos").to_s)
  end

  test "operator scans the machine, confirms two apps, and sees them on the dashboard" do
    # Fixtures ship a managed app (track_planner) so other tests have a
    # populated dashboard to work against. This journey starts from a
    # genuinely clean slate so the empty state it asserts is honest.
    ManagedApp.destroy_all

    visit root_path
    assert_text "No apps on the dashboard yet"

    click_on "Scan for apps"

    assert_text "Scan review"
    assert_text "simple_app"
    assert_text "multi_dest_app"

    within("li", text: "malformed_app") { assert_text "Error" }
    within("li", text: "no_service_app") { assert_text "Error" }

    simple_app = ManagedApp.discovered.find_by!(service_name: "simple_app")

    check "simple_app"
    check "multi_dest_app"
    fill_in "labels_#{simple_app.id}", with: "Simple App (staging box)"

    click_on "Add to dashboard"

    assert_text "2 apps added to the dashboard."
    assert_text "Simple App (staging box)"
    assert_text "multi_dest_app"
    assert_text "status unknown", count: 2
  end

  test "operator views an app's details from the dashboard" do
    app = managed_apps(:track_planner)

    visit root_path
    assert_text app.service_name

    click_on "View"

    assert_current_path managed_app_path(app)
    assert_text app.repo_path
    assert_text "production"
    assert_text "staging"
  end

  test "operator forgets an app from the dashboard and it disappears" do
    app = managed_apps(:track_planner)

    visit root_path
    assert_text app.display_label

    accept_confirm do
      click_on "Forget"
    end

    assert_current_path root_path
    # The flash ("track-planner forgotten.") legitimately echoes the label,
    # so assert the card itself is gone rather than the label text.
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(app)}"
    assert_no_text "Content missing"
    assert_text "No apps on the dashboard yet"
  end

  test "operator renames an app inline from the dashboard" do
    app = managed_apps(:track_planner)

    visit root_path
    assert_text app.service_name

    find("summary", text: "Rename").click
    fill_in ActionView::RecordIdentifier.dom_id(app, :display_name), with: "Track Planner Prod"
    click_on "Save"

    assert_text "Track Planner Prod"
    assert_no_text "Renamed to"
    assert_current_path root_path
  end
end
