require "test_helper"

class CloudflareAccessTest < ActionDispatch::IntegrationTest
  test "a request that came through Cloudflare without an Access token is refused before any page or socket answers" do
    get root_url, headers: { "CF-Ray" => "8a1b2c3d4e5f-IAD" }
    assert_response :forbidden

    get "/cable", headers: { "CF-Ray" => "8a1b2c3d4e5f-IAD" }
    assert_response :forbidden
  end

  test "Evan on the tailnet or localhost reaches the dashboard with no Access token" do
    get root_url

    assert_response :success
  end
end
