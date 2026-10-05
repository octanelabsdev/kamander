require "test_helper"

class Kamander::Kamal::SshClientTest < ActiveSupport::TestCase
  FakeStatus = Struct.new(:successful, :exitstatus) do
    def success?
      successful
    end
  end

  FakeWaitThread = Struct.new(:status, :pid) do
    def join(*) = self
    def value = status
  end

  FakeHangingWaitThread = Struct.new(:pid) do
    def join(timeout = nil) = timeout ? nil : self
  end

  test "builds the expected ssh argv" do
    argv = Kamander::Kamal::SshClient.new.send(:build_argv, user: "deploy", host: "203.0.113.10", command: "docker ps --all")

    assert_equal [
      "ssh",
      "-o", "BatchMode=yes",
      "-o", "ConnectTimeout=5",
      "-o", "StrictHostKeyChecking=accept-new",
      "deploy@203.0.113.10",
      "docker ps --all"
    ], argv
  end

  test "a non-zero exit is reported as a failure without raising" do
    status = FakeStatus.new(false, 1)

    with_popen3(wait_thread: FakeWaitThread.new(status, 999_999), stderr: "permission denied") do
      result = Kamander::Kamal::SshClient.new.capture(host: "203.0.113.10", user: "deploy", command: "docker ps")

      assert_not result.success
      assert_equal "permission denied", result.error
    end
  end

  test "a hung connection is killed and reported as a timeout without raising" do
    with_popen3(wait_thread: FakeHangingWaitThread.new(999_999)) do
      result = Kamander::Kamal::SshClient.new.capture(host: "203.0.113.10", user: "deploy", command: "docker ps", timeout: 0.01)

      assert_not result.success
      assert_match(/timed out/, result.error)
    end
  end

  private

    # Minitest 6 dropped Object#stub into a separate gem we don't depend on,
    # so we swap Open3.popen3 by hand and restore it unconditionally after.
    # Safe only because Rails parallelizes tests across processes, not threads —
    # this global swap would race under threaded parallelization.
    def with_popen3(wait_thread:, stdout: "", stderr: "")
      fake_io = [ StringIO.new, StringIO.new(stdout), StringIO.new(stderr), wait_thread ]
      original_popen3 = Open3.method(:popen3)

      Open3.define_singleton_method(:popen3) { |*_args, **_kwargs, &block| block.call(*fake_io) }
      yield
    ensure
      Open3.define_singleton_method(:popen3, original_popen3)
    end
end
