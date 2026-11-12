require_relative "fake_ssh_client"

# A FakeSshClient that answers like the CI box: RunReader's listing script
# gets the served records whose file names match its glob, as `ls` would on
# the box, and `tail` of a log gets log_output.
class FakeCiBox < FakeSshClient
  attr_accessor :log_output

  def self.serving(*records)
    new(records: records)
  end

  def self.record(id, app: "fixxer", status: "passed", dry_run: false, steps: [])
    { id: id, app: app, sha: "abc1234def5678", branch: "main", dry_run: dry_run, status: status,
      exit_code: status == "passed" ? 0 : 1, started_at: "2026-11-12T09:00:00Z", finished_at: "2026-11-12T09:04:30Z",
      host: "legion", pid: 1, log: "/data/ci/logs/#{id}.log", steps: steps }
  end

  def initialize(records: nil, responses: {})
    super(responses: responses)
    @records = records
  end

  def capture(host:, user:, command:, timeout: 10)
    return Kamander::Kamal::SshClient::Result.new(stdout: log_output.to_s, success: true, error: nil) if command.start_with?("tail ")

    result = super
    return result unless @records

    glob = command[%r{ls -t \S*/(\S+) }, 1]
    matching = @records.select { |record| File.fnmatch(glob, "#{record[:id]}.json") }
    result.with(stdout: matching.map { |record| record.to_json + "\n" }.join + "---\n")
  end
end
