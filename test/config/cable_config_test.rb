require "test_helper"

class CableConfigTest < ActiveSupport::TestCase
  test "development broadcasts reach the browser from Solid Queue's own process" do
    adapter = Rails.application.config_for(:cable, env: "development")[:adapter]

    assert_not_equal "async", adapter, "async only delivers inside one process; job broadcasts (log stream, op console) would never arrive"
  end
end
