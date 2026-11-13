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

  test "with pull before scan on, a repo that can't update is named and the scan still runs" do
    with_untracked_repo("beanlink") do |root|
      Setting.current.update!(scan_root: root, pull_before_scan: true)

      post scan_url

      assert_redirected_to scan_path
      assert_match(/Couldn't update beanlink/, flash[:alert])
      assert_equal "Scan complete.", flash[:notice]
    end
  end

  test "pull before scan is off by default, so a scan on Evan's Mac never touches his working repos" do
    with_untracked_repo("beanlink") do |root|
      Setting.current.update!(scan_root: root)

      post scan_url

      assert_nil flash[:alert]
    end
  end

  private

    # A repo with no upstream: git pull fails, the way a real refusal would.
    def with_untracked_repo(name)
      Dir.mktmpdir do |root|
        system("git", "init", "-q", File.join(root, name), exception: true)
        yield root
      end
    end
end
