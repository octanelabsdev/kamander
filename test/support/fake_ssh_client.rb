# Test double for Kamander::Kamal::SshClient. Canned per-host responses:
# a String is the docker ps stdout for a successful call; :unreachable
# simulates a dead/unauthenticated host. Every call is recorded so tests
# can assert batching (e.g. one call per shared host).
class FakeSshClient
  Call = Struct.new(:host, :user, :command, keyword_init: true)

  attr_reader :calls

  def initialize(responses: {})
    @responses = responses
    @calls = []
  end

  def capture(host:, user:, command:, timeout: 10)
    @calls << Call.new(host: host, user: user, command: command)

    response = @responses.fetch(host, "")

    if response == :unreachable
      Kamander::Kamal::SshClient::Result.new(stdout: "", success: false, error: "connection unreachable")
    else
      Kamander::Kamal::SshClient::Result.new(stdout: response, success: true, error: nil)
    end
  end
end
