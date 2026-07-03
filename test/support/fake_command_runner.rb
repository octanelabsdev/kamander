# Test double for Kamander::Kamal::CommandRunner. Canned per-command responses,
# keyed by the exact argv array: { lines: [...], exit_status: N }. exit_status
# may be nil to simulate a spawn failure, same as the real runner. Unlisted
# commands yield nothing and succeed. Every call is recorded so tests can
# assert what ran, where, and with what env.
class FakeCommandRunner
  Call = Struct.new(:command, :chdir, :env, keyword_init: true)

  attr_reader :calls

  def initialize(responses: {})
    @responses = responses
    @calls = []
  end

  def stream(command:, chdir:, env: {})
    @calls << Call.new(command: command, chdir: chdir, env: env)

    canned = @responses.fetch(command, { lines: [], exit_status: 0 })
    canned[:lines].each { |line| yield line.chomp }

    Kamander::Kamal::CommandResult.new(exit_status: canned[:exit_status], success: canned[:exit_status] == 0)
  end
end
