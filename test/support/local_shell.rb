# An SshClient that runs the command in a local shell, so the scripts meant
# for the CI box (jq, /proc checks, kill) are exercised, not stubbed.
class LocalShell
  def capture(host:, user:, command:, timeout: 10)
    stdout, stderr, status = Open3.capture3("sh", "-c", command)
    Kamander::Kamal::SshClient::Result.new(stdout: stdout, success: status.success?, error: status.success? ? nil : stderr)
  end
end
