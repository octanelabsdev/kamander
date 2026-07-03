require "test_helper"

class LifecycleButtonsHelperTest < ActionView::TestCase
  test "confirm text names the destination and its hosts" do
    destination = app_destinations(:track_planner_production)

    assert_equal "Restart production on 5.78.71.207?", lifecycle_confirm_text(:restart, destination)
  end

  test "confirm text falls back to base for a nil-named destination" do
    destination = app_destinations(:contractor_link_base)

    assert_equal "Stop base on 3.14.15.92?", lifecycle_confirm_text(:stop, destination)
  end
end
