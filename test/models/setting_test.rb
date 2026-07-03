require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "current returns the singleton settings row" do
    assert_equal settings(:current), Setting.current
    assert_equal 1, Setting.count
  end

  test "current creates a settings row with the default scan_root when none exists" do
    Setting.delete_all
    setting = Setting.current
    assert_equal "~/Development", setting.scan_root
    assert_equal "deploy", setting.default_ssh_user
    assert_equal 1, Setting.count
  end
end
