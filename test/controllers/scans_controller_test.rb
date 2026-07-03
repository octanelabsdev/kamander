require "test_helper"

class ScansControllerTest < ActionDispatch::IntegrationTest
  setup do
    Setting.current.update!(scan_root: file_fixture("repos").to_s)
  end

  test "trigger scan → review page lists candidates" do
    assert_difference "ManagedApp.count", 7 do
      post scan_url
    end
    assert_redirected_to scan_path

    get scan_path
    assert_response :success
    assert_match "simple_app", response.body
  end

  test "parse-error badge shows" do
    post scan_url

    get scan_path
    assert_response :success
    assert_match "malformed_app", response.body
  end
end
