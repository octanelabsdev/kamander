require "test_helper"

class Kamander::Ci::BoxHealthTest < ActiveSupport::TestCase
  test "Evan sees the box's load, memory, disks, GPU, services and battery from one call" do
    box = FakeSshClient.new(responses: { "ci-box.test" => BOX_HEALTH_OUTPUT })

    health = Kamander::Ci::BoxHealth.new(host: "ci-box.test", user: "ci", ssh_client: box).call

    assert health.success?
    assert_equal 1, box.calls.size
    assert_equal "ci", box.calls.sole.user
    assert_equal 32, health.cpus
    assert_equal [ 3.21, 2.5, 1.75 ], health.load
    assert_equal 0.375, health.memory_used_ratio
    assert_equal 0.25, health.swap_used_ratio
    assert_equal({ "/" => [ 214_748_364, 524_288_000 ], "/data" => [ 104_857_600, 1_048_576_000 ] }, health.disks)
    assert_equal 54, health.gpu_temp
    assert_equal({ "postgres" => "up", "ollama" => "down", "tailscale" => "up" }, health.services)
    assert_equal [ 80, "Not charging", 80 ], [ health.battery, health.battery_status, health.battery_limit ]
  end

  test "anything the box can't report stays unknown instead of failing the strip" do
    health = Kamander::Ci::BoxHealth.new(host: "ci-box.test", user: "ci",
      ssh_client: FakeSshClient.new(responses: { "ci-box.test" => "cpus=8\nload=0.10 0.20 0.30\n" })).call

    assert health.success?
    assert_nil health.gpu_temp
    assert_nil health.memory_used_ratio
    assert_nil health.battery
    assert_equal({ "postgres" => "unknown", "ollama" => "unknown", "tailscale" => "unknown" }, health.services)
  end

  test "an unreachable box comes back as an error, not an exception" do
    health = Kamander::Ci::BoxHealth.new(host: "ci-box.test", user: "ci",
      ssh_client: FakeSshClient.new(responses: { "ci-box.test" => :unreachable })).call

    assert_not health.success?
    assert_equal "connection unreachable", health.error
  end

  test "the box script runs in a plain shell without erroring where /proc and the tools are missing" do
    health = Kamander::Ci::BoxHealth.new(host: "local", user: "me", ssh_client: LocalShell.new).call

    assert health.success?, health.error
    assert_includes %w[up down unknown], health.services["postgres"]
  end
end
