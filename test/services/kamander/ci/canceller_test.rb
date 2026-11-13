require "test_helper"

class Kamander::Ci::CancellerTest < ActiveSupport::TestCase
  ID = "fixxer-20261112T090000Z-11".freeze

  setup do
    @root = Dir.mktmpdir
    @runs_dir = File.join(@root, "runs")
    @proc_root = File.join(@root, "proc")
    @pid = Process.spawn("sleep", "30")
  end

  teardown do
    Process.kill("KILL", @pid) rescue Errno::ESRCH
    Process.wait(@pid) rescue Errno::ECHILD
    FileUtils.remove_entry(@root)
  end

  test "cancelling a live run sends TERM to the pid that is running that exact record" do
    write_cmdline [ "bash", "-l", "-c", 'source "$0"; rm -f "$0"; run "$@"', "/data/ci/.remote-ci-Ab12.sh",
                    "fixxer", "/data/ci/logs/#{ID}.log", File.join(@runs_dir, "#{ID}.json") ]

    result = cancel

    assert result.success?, result.message
    assert_equal "TERM", Signal.signame(Process.wait2(@pid).last.termsig)
  end

  test "a pid now running something else is never signalled" do
    write_cmdline [ "postgres: checkpointer" ]

    result = cancel

    assert_not result.success?
    assert_includes result.message, "is not this run any more"
    assert_nil Process.wait(@pid, Process::WNOHANG), "the unrelated process must still be running"
  end

  test "a pid now running a different CI run is never signalled" do
    write_cmdline [ "bash", "-l", "-c", 'source "$0"; rm -f "$0"; run "$@"', "/data/ci/.remote-ci-Cd34.sh",
                    "beanlink", "/data/ci/logs/beanlink-20261112T100000Z-12.log", File.join(@runs_dir, "beanlink-20261112T100000Z-12.json") ]

    assert_not cancel.success?
    assert_nil Process.wait(@pid, Process::WNOHANG), "another run's process must still be running"
  end

  test "a pid that is gone reports the run as already finished" do
    result = cancel

    assert_not result.success?
    assert_includes result.message, "no longer running"
  end

  test "with the CI box unreachable the cancel says so" do
    result = Kamander::Ci::Canceller.new(host: "ci-box.test", user: "ci",
      ssh_client: FakeSshClient.new(responses: { "ci-box.test" => :unreachable })).call(ci_run)

    assert_not result.success?
    assert_includes result.message, "CI box unreachable"
  end

  private

    def cancel
      Kamander::Ci::Canceller.new(host: "local", user: "me", ssh_client: LocalShell.new,
        runs_dir: @runs_dir, proc_root: @proc_root).call(ci_run)
    end

    def ci_run
      Kamander::Ci::Run.from_record(FakeCiBox.record(ID, status: "running").merge(pid: @pid).stringify_keys, alive: true)
    end

    def write_cmdline(argv)
      FileUtils.mkdir_p(File.join(@proc_root, @pid.to_s))
      File.binwrite(File.join(@proc_root, @pid.to_s, "cmdline"), argv.join("\0") + "\0")
    end
end
