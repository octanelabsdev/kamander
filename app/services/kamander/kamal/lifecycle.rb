module Kamander
  module Kamal
    # Runs one lifecycle Operation to completion: builds the verb's command,
    # transitions queued -> running -> succeeded/failed, and streams output
    # into operation.output as it arrives. Restart goes over SshClient
    # (server-side docker, no kamal involved); reboot/start/stop run the
    # repo's own bin/kamal via CommandRunner. Pure given its injected
    # clients — no real SSH/subprocess here, that's SshClient/CommandRunner's job.
    class Lifecycle
      def initialize(operation:, command_runner: Kamander::Kamal.command_runner, ssh_client: Kamander::Kamal.ssh_client)
        @operation = operation
        @command_runner = command_runner
        @ssh_client = ssh_client
      end

      def call
        case @operation.verb
        when "restart" then restart!
        when "reboot", "start" then boot!
        when "stop" then stop!
        end

        @operation
      end

      private

      def restart!
        containers_by_host = running_app_containers.group_by { |container| container["host"] }
        return block!(command: "docker restart", message: "nothing running to restart") if containers_by_host.empty?

        commands = containers_by_host.transform_values { |containers| "docker restart #{containers.map { |c| c["name"] }.join(" ")}" }
        begin_running!(commands.values.join("; "))

        results = commands.map do |host, docker_command|
          result = @ssh_client.capture(host: host, user: @operation.app_destination.effective_ssh_user, command: docker_command)
          append_line!("#{host}: #{result.success? ? (result.stdout.presence || "restarted") : result.error}")
          result
        end

        success = results.all?(&:success?)
        complete!(success: success, exit_status: success ? 0 : 1)
      end

      def boot!
        argv = kamal_argv("boot")
        version = latest_known_version
        return block!(command: argv.join(" "), message: "no known deployed version — deploy from the repo first") if version.blank?

        run_kamal(argv + [ "--version", version ])
      end

      def stop!
        run_kamal(kamal_argv("stop"))
      end

      def run_kamal(argv)
        begin_running!(argv.join(" "))
        result = @command_runner.stream(command: argv, chdir: @operation.managed_app.repo_path) { |line| append_line!(line) }
        complete!(success: result.success?, exit_status: result.exit_status)
      end

      def kamal_argv(verb)
        destination = @operation.app_destination
        argv = [ "bin/kamal", "app", verb ]
        argv.push("-d", destination.name) if destination.name.present?
        argv
      end

      def running_app_containers
        app_containers.select { |container| container["state"] == "running" }
      end

      # Running first, then exited — the last known deployed version even if the app is
      # currently down. No timestamp on a container to break ties among simultaneous
      # versions mid-deploy, so the first match wins.
      def latest_known_version
        running = running_app_containers
        (running.presence || app_containers).filter_map { |container| container["version"] }.first
      end

      def app_containers
        status = @operation.app_destination.destination_status
        return [] unless status

        status.containers.select { |container| container["kind"] == "app" }
      end

      def begin_running!(command)
        @operation.update!(command: command, status: :running, started_at: Time.current)
      end

      def append_line!(line)
        @operation.update!(output: "#{@operation.output}#{line}\n")
        @operation.broadcast_append_to @operation,
          target: ActionView::RecordIdentifier.dom_id(@operation, :output),
          html: "<div>#{ERB::Util.html_escape(line)}</div>"
      end

      # Shared terminal-state bookkeeping for both a normal finish and a pre-flight block —
      # either way the destination's lock frees and a status re-poll is worth chaining.
      def complete!(success:, exit_status: nil)
        @operation.update!(status: success ? :succeeded : :failed, exit_status: exit_status, finished_at: Time.current)
        StatusPollJob.perform_later(managed_app_id: @operation.managed_app_id)
      end

      def block!(command:, message:)
        @operation.update!(command: command, started_at: Time.current)
        append_line!(message)
        complete!(success: false)
      end
    end
  end
end
