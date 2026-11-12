require "test_helper"

class BoxHealthsControllerTest < ActionDispatch::IntegrationTest
  teardown { Kamander::Kamal.ssh_client = nil }

  test "the CI page offers box health on click, without calling the box first" do
    box = Kamander::Kamal.ssh_client = FakeCiBox.serving

    get ci_runs_url

    assert_select "turbo-frame#box_health a[href=?]", ci_box_health_path, text: "Load box health"
    assert_empty box.calls.reject { |call| call.command.include?("ls -t ") }
  end

  test "Evan loads box health and sees load, memory, disks, services and battery, with trouble flagged" do
    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: { "legion" => BOX_HEALTH_OUTPUT.sub("disk /data=104857600", "disk /data=1048576") })

    get ci_box_health_url

    assert_response :success
    assert_select "turbo-frame#box_health #box_health_stats" do
      assert_select "[data-stat=Load]", text: /3\.21 · 2\.50 · 1\.75.*32 CPUs/m
      assert_select "[data-stat=Memory]", text: /38%/
      assert_select "[data-stat='Disk /data'].border-amber-700", text: /free of/
      assert_select "[data-service=postgres][data-state=up]"
      assert_select "[data-service=ollama][data-state=down]"
      assert_select "[data-stat=Battery]", text: /80%.*limit 80%/m
    end
  end

  test "a box that can't report a value shows unknown, and an unreachable box shows the error in the strip" do
    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: { "legion" => "cpus=8\n" })
    get ci_box_health_url
    assert_select "[data-stat=GPU]", text: /unknown/

    Kamander::Kamal.ssh_client = FakeSshClient.new(responses: { "legion" => :unreachable })
    get ci_box_health_url
    assert_select "turbo-frame#box_health [role=alert]", text: /CI box unreachable: connection unreachable/
  end
end
