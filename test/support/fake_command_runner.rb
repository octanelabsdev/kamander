# Test double for Kamander::Kamal::CommandRunner. Canned per-command responses,
# keyed by the exact argv array: { lines: [...], exit_status: N }. exit_status
# may be nil to simulate a spawn failure, same as the real runner. Unlisted
# commands yield nothing and succeed. Every call is recorded so tests can
# assert what ran, where, and with what env.
#
# spawn takes the same responses: lines go to out:, on_spawn runs once the
# command has "started", exit_status: nil never finishes, raise: raises.
class FakeCommandRunner
  Call = Struct.new(:command, :chdir, :env, keyword_init: true)
  Background = Struct.new(:exit_status, :stopped) do
    def finished? = !exit_status.nil?
    def success? = exit_status == 0
    def stop = self.stopped = true
  end

  attr_reader :calls, :spawned

  def initialize(responses: {})
    @responses = responses
    @calls = []
    @spawned = []
  end

  def spawn(command:, chdir:, out:, env: {})
    @calls << Call.new(command: command, chdir: chdir, env: env)

    canned = @responses.fetch(command, {})
    raise canned[:raise] if canned[:raise]

    File.write(out, Array(canned[:lines]).map { |line| "#{line}\n" }.join)
    canned[:on_spawn]&.call
    Background.new(canned.fetch(:exit_status, 0), false).tap { |background| @spawned << background }
  end

  def stream(command:, chdir:, env: {})
    @calls << Call.new(command: command, chdir: chdir, env: env)

    canned = @responses.fetch(command, { lines: [], exit_status: 0 })
    canned[:lines].each { |line| yield line.chomp }

    Kamander::Kamal::CommandResult.new(exit_status: canned[:exit_status], success: canned[:exit_status] == 0)
  end
end
