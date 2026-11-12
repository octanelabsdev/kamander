require "test_helper"

class Kamander::Ci::RunReaderTest < ActiveSupport::TestCase
  RUN_CMDLINE = [ "bash", "-l", "-c", 'source "$0"; rm -f "$0"; run "$@"', "/data/ci/.remote-ci-Ab12.sh",
                  "fixxer", "git@github.com:octanelabsdev/fixxer.git", "abc123", "main", "0" ].freeze

  setup do
    @root = Dir.mktmpdir
    @runs_dir = File.join(@root, "runs")
    @proc_root = File.join(@root, "proc")
    FileUtils.mkdir_p([ @runs_dir, @proc_root ])
  end

  teardown { FileUtils.remove_entry(@root) }

  test "Evan sees recent runs newest first, with steps, duration, and the record name as id" do
    write_record "fixxer-20261112T090000Z-11", status: "passed", exit_code: 0,
      started_at: "2026-11-12T09:00:00Z", finished_at: "2026-11-12T09:04:30Z",
      steps: [ { name: "Style: Ruby", result: "passed", took: "1.2s" }, { name: "Tests: Rails", result: "passed", took: "3m4s" } ]
    write_record "beanlink-20261112T100000Z-12", app: "beanlink", status: "failed", exit_code: 1,
      started_at: "2026-11-12T10:00:00Z", finished_at: "2026-11-12T10:01:00Z",
      steps: [ { name: "Style: Ruby", result: "passed", took: "1s" }, { name: "Tests: Rails", result: "failed", took: "50s" } ]

    listing = read

    assert listing.success?
    assert_equal %w[beanlink-20261112T100000Z-12 fixxer-20261112T090000Z-11], listing.runs.map(&:id)

    failed = listing.runs.first
    assert_equal "failed", failed.state
    assert_equal [ "Tests: Rails" ], failed.steps.reject(&:passed?).map(&:name)
    assert_equal 60, failed.duration
    assert_equal "abc1234", failed.short_sha
  end

  test "a running record is live only while its pid runs this exact record" do
    write_record "fixxer-20261112T110000Z-21", status: "running", pid: 4101
    write_proc 4101, RUN_CMDLINE + [ log_path("fixxer-20261112T110000Z-21"), record_path("fixxer-20261112T110000Z-21") ]

    run = read.runs.sole

    assert run.live?
    assert_equal "running", run.state
  end

  test "a run that died in a reboot shows as lost, not running" do
    write_record "fixxer-20261112T120000Z-31", status: "running", pid: 4201
    write_record "fixxer-20261112T120100Z-32", status: "queued", pid: 4202
    write_record "fixxer-20261112T120200Z-33", status: "running", pid: 4203
    write_proc 4202, [ "/usr/sbin/sshd", "-D" ]
    write_proc 4203, RUN_CMDLINE + [ log_path("other"), record_path("fixxer-20261112T999999Z-99") ]

    runs = read.runs

    assert_equal %w[lost lost lost], runs.map(&:state)
    assert runs.none?(&:live?)
  end

  test "older records without a pid or -<n> suffix still list, and an unfinished one shows as lost" do
    write_record "fixxer-20261101T090000Z", status: "passed", exit_code: 0, pid: nil, started_at: "2026-11-01T09:00:00Z"
    write_record "fixxer-20261101T080000Z", status: "running", pid: nil, started_at: "2026-11-01T08:00:00Z"

    runs = read(app: "fixxer").runs

    assert_equal %w[fixxer-20261101T090000Z fixxer-20261101T080000Z], runs.map(&:id)
    assert_equal %w[passed lost], runs.map(&:state)
  end

  test "a run killed by Cancel shows as cancelled" do
    write_record "fixxer-20261112T130000Z-41", status: "error", exit_code: 143, finished_at: "2026-11-12T13:00:05Z"

    assert_equal "cancelled", read.runs.sole.state
  end

  test "filtering by app returns only that repo's runs, not a repo whose name starts the same" do
    write_record "fixxer-20261112T140000Z-51"
    write_record "fixxer-docs-20261112T140100Z-52", app: "fixxer-docs"

    assert_equal [ "fixxer" ], read(app: "fixxer").runs.map(&:app)
  end

  test "an empty runs directory is an empty listing, not an error" do
    listing = read

    assert listing.success?
    assert_empty listing.runs
  end

  test "an unreachable CI box comes back as an error instead of raising" do
    fake = FakeSshClient.new(responses: { "legion" => :unreachable })

    listing = Kamander::Ci::RunReader.new(host: "legion", user: "octane", ssh_client: fake).call

    assert_not listing.success?
    assert_equal "connection unreachable", listing.error
    assert_empty listing.runs
    assert_equal "octane", fake.calls.sole.user
  end

  test "an app name that isn't a plain repo name is refused before anything reaches the shell" do
    fake = FakeSshClient.new

    listing = Kamander::Ci::RunReader.new(host: "legion", user: "octane", ssh_client: fake).call(app: "x; rm -rf /")

    assert_not listing.success?
    assert_empty fake.calls
  end

  private

    def read(**options)
      Kamander::Ci::RunReader.new(host: "local", user: "me", ssh_client: LocalShell.new,
        runs_dir: @runs_dir, proc_root: @proc_root).call(**options)
    end

    def write_record(id, app: "fixxer", status: "passed", pid: 999, exit_code: nil, steps: [],
      started_at: "2026-11-12T08:00:00Z", finished_at: nil)
      record = { app: app, sha: "abc1234def5678", branch: "main", dry_run: false, status: status, exit_code: exit_code,
                 started_at: started_at, finished_at: finished_at, host: "legion", pid: pid,
                 log: log_path(id), steps: steps }
      record.delete(:pid) if pid.nil?
      File.write(record_path(id), JSON.pretty_generate(record))
    end

    def write_proc(pid, argv)
      FileUtils.mkdir_p(File.join(@proc_root, pid.to_s))
      File.binwrite(File.join(@proc_root, pid.to_s, "cmdline"), argv.join("\0") + "\0")
    end

    def record_path(id) = File.join(@runs_dir, "#{id}.json")
    def log_path(id) = "/data/ci/logs/#{id}.log"

    # Runs the reader's real script through a local shell, so the jq and
    # /proc logic that will run on the box is exercised, not stubbed.
    class LocalShell
      def capture(host:, user:, command:, timeout: 10)
        stdout, stderr, status = Open3.capture3("sh", "-c", command)
        Kamander::Kamal::SshClient::Result.new(stdout: stdout, success: status.success?, error: status.success? ? nil : stderr)
      end
    end
end
