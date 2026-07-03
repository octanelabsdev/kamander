require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "change scan root, next scan uses it" do
    new_root = file_fixture("repos").to_s

    patch setting_url, params: { setting: { scan_root: new_root, default_ssh_user: "deploy" } }

    assert_redirected_to edit_setting_path
    assert_equal new_root, Setting.current.reload.scan_root

    scanned = Kamander::Kamal::ConfigScanner.new(scan_root: Setting.current.expanded_scan_root).call
    assert_includes scanned.map { |app| File.basename(app.repo_path) }, "simple_app"
  end
end
