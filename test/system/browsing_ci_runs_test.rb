require "application_system_test_case"

class BrowsingCiRunsTest < ApplicationSystemTestCase
  setup { @original_ssh_client = Kamander::Kamal.ssh_client }
  teardown { Kamander::Kamal.ssh_client = @original_ssh_client }

  test "Evan opens CI from the dashboard, spots the failed step, and reads that run's log" do
    box = FakeCiBox.serving(
      FakeCiBox.record("beanlink-20261112T100000Z-12", app: "beanlink", status: "failed", steps: [
        { name: "Style: Ruby", result: "passed", took: "1s" }, { name: "Tests: Rails", result: "failed", took: "50s" }
      ]),
      FakeCiBox.record("fixxer-20261112T090000Z-11")
    )
    box.log_output = "Running 162 tests\nFailure: BeanTest#test_roast\n"
    Kamander::Kamal.ssh_client = box

    visit root_path
    within("nav") { click_on "CI" }

    within("#ci_run_beanlink-20261112T100000Z-12") do
      assert_selector "[data-step-result=failed]", text: "Tests: Rails"
      click_on "beanlink"
    end

    assert_selector "h1", text: "beanlink"
    assert_text "Failure: BeanTest#test_roast"
  end
end
