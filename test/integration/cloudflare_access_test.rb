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

  test "signed in through Access, Evan sees his email and a Log out link to Cloudflare's logout" do
    get root_url, env: { Kamander::CloudflareAccessGate::IDENTITY => "evan@example.com" }

    assert_select "nav", text: /evan@example\.com/
    assert_select "nav a[href='/cdn-cgi/access/logout']", text: "Log out"
  end

  test "on the tailnet there's no Access session, so no Log out link" do
    get root_url, headers: { "Kamander-Access-Email" => "spoofed@example.com" }

    assert_select "nav a[href='/cdn-cgi/access/logout']", count: 0
    assert_no_match "spoofed@example.com", response.body
  end
end
