require "test_helper"

class StatusRefreshesControllerTest < ActionDispatch::IntegrationTest
  test "operator clicks Refresh and a status poll is enqueued" do
    assert_enqueued_with(job: StatusPollJob) do
      post status_refresh_url
    end

    assert_redirected_to root_path
  end

  test "a per-app refresh enqueues a poll scoped to just that app" do
    app = managed_apps(:track_planner)

    assert_enqueued_with(job: StatusPollJob, args: [ { managed_app_id: app.id } ]) do
      post status_refresh_url, params: { managed_app_id: app.id }
    end

    assert_redirected_to root_path
  end

  test "refresh is rejected for an app that is not managed" do
    discovered = managed_apps(:contractor_link)

    post status_refresh_url, params: { managed_app_id: discovered.id }

    assert_response :not_found
  end
end
