module Kamander
  module Ci
    # Runs remote-ci itself so all of ci-box's checks apply; stops it once the box has the run, which outlives it.
    class Launcher
      POLL_INTERVAL = 2
      POLLS = 60

      def initialize(launch:, host:, user:, ssh_client: Kamander::Kamal.ssh_client,
        command_runner: Kamander::Kamal.command_runner, poll_interval: POLL_INTERVAL)
        @launch = launch
        @host = host
        @user = user
        @command_runner = command_runner
        @poll_interval = poll_interval
        @reader = RunReader.new(host: host, user: user, ssh_client: ssh_client)
      end

      def call
        before = runs
        return fail!("CI box unreachable: #{before.error}") unless before.success?

        head = Checkout.read(app.repo_path)&.sha
        return fail!("HEAD is now #{head.to_s.first(7)}, not #{@launch.short_sha}. Reload and confirm again.") unless head == @launch.sha

        Tempfile.create("ci-launch") { |output| launch_and_wait(output.path, known: before.runs.map(&:id)) }
      rescue SystemCallError => e
        fail!("kamander: #{e.message}")
      end

      private

        def launch_and_wait(output, known:)
          process = @command_runner.spawn(command: command, chdir: app.repo_path, out: output,
            env: { "REMOTE_CI_HOST" => "#{@user}@#{@host}" })

          POLLS.times do
            finished = process.finished?
            if (run = runs.runs.find { |record| record.sha == @launch.sha && known.exclude?(record.id) })
              process.stop
              return @launch.update!(status: :started, run_id: run.id, output: read(output))
            end
            return fail!(read(output)) if finished

            sleep @poll_interval
          end

          process.stop
          fail!("#{read(output)}kamander: no run record on the box after #{POLLS * POLL_INTERVAL / 60} minutes; check the CI page.")
        end

        def app = @launch.managed_app

        def command = [ "remote-ci", *("--dry-run" if @launch.dry_run) ]

        def runs = @reader.call(app: app.ci_name, limit: 10)

        def read(path) = File.read(path).gsub(RunReader::ANSI_ESCAPE, "")

        def fail!(output) = @launch.update!(status: :failed, output: output)
    end
  end
end
