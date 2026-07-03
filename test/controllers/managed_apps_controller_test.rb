require "test_helper"

class ManagedAppsControllerTest < ActionDispatch::IntegrationTest
  test "bulk confirm moves to dashboard" do
    discovered = managed_apps(:contractor_link)

    post confirm_managed_apps_url, params: { managed_app_ids: [ discovered.id ], commit: "confirm" }

    assert_redirected_to root_path
    assert discovered.reload.managed?
  end

  test "hide removes from review" do
    discovered = managed_apps(:contractor_link)

    post confirm_managed_apps_url, params: { managed_app_ids: [ discovered.id ], commit: "hide" }

    assert_redirected_to scan_path
    assert discovered.reload.hidden?
  end

  test "operator labels an app while confirming and the label sticks" do
    discovered = managed_apps(:contractor_link)

    post confirm_managed_apps_url,
      params: { managed_app_ids: [ discovered.id ], commit: "confirm", labels: { discovered.id.to_s => "My Label" } }

    assert_redirected_to root_path
    discovered.reload
    assert discovered.managed?
    assert_equal "My Label", discovered.display_name
  end

  test "confirming without a label leaves an existing display_name untouched" do
    labeled = managed_apps(:old_project)

    post confirm_managed_apps_url, params: { managed_app_ids: [ labeled.id ], commit: "confirm" }

    assert_redirected_to root_path
    labeled.reload
    assert labeled.managed?
    assert_equal "Old Project (retired)", labeled.display_name
  end

  test "rename sticks" do
    app = managed_apps(:contractor_link)

    patch managed_app_url(app), params: { managed_app: { display_name: "Contractor Link" } }

    assert_redirected_to app
    assert_equal "Contractor Link", app.reload.display_name
  end

  test "forget disappears" do
    app = managed_apps(:contractor_link)

    assert_difference "ManagedApp.count", -1 do
      delete managed_app_url(app)
    end

    assert_redirected_to root_path
  end

  test "empty state CTA" do
    managed_apps(:track_planner).update!(status: :hidden)

    get root_url

    assert_response :success
    assert_match "Scan for apps", response.body
  end
end
