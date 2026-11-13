require_relative "fake_ssh_client"

# A FakeSshClient that answers like the CI box: RunReader's listing script
# gets the served records whose file names match its glob, as `ls` would on
# the box, and `tail` of a log gets log_output. Ids in live: are reported as
# still running, the way the box's /proc check reports them. Any other command
# (a cancel) gets its canned response by host, as in FakeSshClient.
class FakeCiBox < FakeSshClient
  attr_accessor :log_output
  attr_reader :records

  def self.serving(*records, live: [], responses: {})
    new(records: records, live: live, responses: responses)
  end

  def self.record(id, app: "fixxer", status: "passed", dry_run: false, steps: [], sha: "abc1234def5678")
    { id: id, app: app, sha: sha, branch: "main", dry_run: dry_run, status: status,
      exit_code: status == "passed" ? 0 : 1, started_at: "2026-11-12T09:00:00Z", finished_at: "2026-11-12T09:04:30Z",
      host: "ci-box.test", pid: 1, log: "/data/ci/logs/#{id}.log", steps: steps }
  end

  def initialize(records: nil, live: [], responses: {})
    super(responses: responses)
    @records = records
    @live = live
  end

  def capture(host:, user:, command:, timeout: 10)
    return Kamander::Kamal::SshClient::Result.new(stdout: log_output.to_s, success: true, error: nil) if command.start_with?("tail ")

    result = super
    return result unless @records && command.include?("ls -t ")

    glob = command[%r{ls -t \S*/(\S+) }, 1]
    matching = @records.select { |record| File.fnmatch(glob, "#{record[:id]}.json") }
    live = matching.map { |record| record[:id] } & @live
    result.with(stdout: (matching.map(&:to_json) + [ "---" ] + live).join("\n") + "\n")
  end
end
