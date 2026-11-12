require "test_helper"

class Kamander::Kamal::CommandRunnerTest < ActiveSupport::TestCase
  test "streams output lines in the order they arrive" do
    lines = []
    script = "STDOUT.puts 'one'; STDOUT.flush; STDERR.puts 'two'; STDERR.flush; STDOUT.puts 'three'; STDOUT.flush"

    result = runner.stream(command: [ "ruby", "-e", script ], chdir: Dir.pwd) { |line| lines << line }

    assert_equal %w[one two three], lines
    assert result.success?
  end

  test "returns the exit status and failure for a non-zero exit" do
    lines = []

    result = runner.stream(command: [ "ruby", "-e", "STDOUT.puts 'failing'; exit 3" ], chdir: Dir.pwd) { |line| lines << line }

    assert_equal [ "failing" ], lines
    assert_not result.success?
    assert_equal 3, result.exit_status
  end

  test "a nonexistent command yields a failure result, not an exception" do
    lines = []

    result = runner.stream(command: [ "kamander_test_command_that_does_not_exist" ], chdir: Dir.pwd) { |line| lines << line }

    assert_not result.success?
    assert_nil result.exit_status
    assert_equal 1, lines.size
  end

  test "the subprocess runs in the given working directory" do
    lines = []

    Dir.mktmpdir do |dir|
      real_dir = File.realpath(dir)
      runner.stream(command: [ "ruby", "-e", "puts Dir.pwd" ], chdir: real_dir) { |line| lines << line }

      assert_equal [ real_dir ], lines
    end
  end

  test "the subprocess runs under an unbundled env" do
    lines = []

    runner.stream(command: [ "ruby", "-e", "puts ENV['BUNDLE_GEMFILE'].inspect" ], chdir: Dir.pwd) { |line| lines << line }

    assert_equal [ "nil" ], lines
  end

  test "a spawned command runs in the background with its output in a file" do
    Tempfile.create("out") do |out|
      background = runner.spawn(command: [ "sh", "-c", "echo started; echo oops >&2; exit 3" ], chdir: Dir.pwd, out: out.path)

      sleep 0.05 until background.finished?
      assert_not background.success?
      assert_equal "started\noops\n", File.read(out.path)
    end
  end

  test "stopping a spawned command also stops the children it started" do
    Tempfile.create("out") do |out|
      background = runner.spawn(command: [ "sh", "-c", "sleep 30 & echo $!; wait" ], chdir: Dir.pwd, out: out.path)
      sleep 0.05 until File.size(out.path).positive?
      child = Integer(File.read(out.path))

      background.stop

      assert_raises(Errno::ESRCH) { 20.times { Process.kill(0, child); sleep 0.05 } }
    end
  end

  private

    def runner
      Kamander::Kamal::CommandRunner.new
    end
end
