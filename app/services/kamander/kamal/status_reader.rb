module Kamander
  module Kamal
    # Reads live container status for a set of AppDestinations. Unit of work is
    # the (host, ssh_user) pair, not the destination — hosts running several
    # apps get exactly one SSH + one `docker ps` between them. Never persists
    # anything (that's StatusWriter); a dead host isolates to the destinations
    # that need it and never blocks the rest of the batch.
    class StatusReader
      DOCKER_PS_COMMAND = "docker ps --all --no-trunc --format '{{json .}}'"

      def initialize(destinations:, ssh_client: SshClient.new)
        @destinations = destinations
        @ssh_client = ssh_client
      end

      def call
        host_reports = fetch_host_reports
        checked_at = Time.current

        @destinations.map { |destination| build_report(destination, host_reports, checked_at) }
      end

      private

      def fetch_host_reports
        pairs = @destinations.flat_map { |destination| destination.server_ips.map { |ip| [ ip, destination.effective_ssh_user ] } }.uniq

        pairs
          .map { |host, user| Thread.new { [ [ host, user ], fetch_host_report(host, user) ] } }
          .to_h { |thread| thread.value }
      end

      def fetch_host_report(host, user)
        result = @ssh_client.capture(host: host, user: user, command: DOCKER_PS_COMMAND)

        if result.success?
          HostReport.new(host: host, user: user, reachable: true, containers: parse_containers(result.stdout), error: nil)
        else
          HostReport.new(host: host, user: user, reachable: false, containers: [], error: result.error)
        end
      rescue StandardError => e
        HostReport.new(host: host, user: user, reachable: false, containers: [], error: e.message)
      end

      def parse_containers(stdout)
        stdout.each_line.filter_map do |line|
          next if line.strip.empty?

          raw = JSON.parse(line)
          { name: raw["Names"], state: raw["State"], status_text: raw["Status"], image: raw["Image"] }
        rescue JSON::ParserError
          nil
        end
      end

      def build_report(destination, host_reports, checked_at)
        reports_by_host = destination.server_ips.index_with { |ip| host_reports.fetch([ ip, destination.effective_ssh_user ]) }
        unreachable = reports_by_host.values.reject(&:reachable?)

        if unreachable.any?
          return DestinationReport.new(
            app_destination_id: destination.id,
            state: :unreachable,
            containers: [],
            error: unreachable.map(&:error).compact.join("; "),
            checked_at: checked_at
          )
        end

        containers = expected_containers(destination, reports_by_host)

        DestinationReport.new(
          app_destination_id: destination.id,
          state: calculate_state(containers),
          containers: containers,
          error: nil,
          checked_at: checked_at
        )
      end

      def expected_containers(destination, reports_by_host)
        service = destination.managed_app.service_name

        role_slots = destination.servers.flat_map do |role, ips|
          ips.map { |host| role_slot(service: service, role: role, destination: destination, host: host, reports_by_host: reports_by_host) }
        end

        accessory_slots = destination.accessory_names.map do |accessory_name|
          accessory_slot(service: service, accessory_name: accessory_name, destination: destination, reports_by_host: reports_by_host)
        end

        proxy_slots = reports_by_host.keys.map { |host| proxy_slot(host: host, reports_by_host: reports_by_host) }

        role_slots + accessory_slots + proxy_slots
      end

      # Ground truth (kamal configuration/role.rb): container_prefix = [service, role, destination].compact.join("-");
      # container_name = [container_prefix, version].compact.join("-"). Match by prefix, never exact — the trailing
      # segment is the deploy SHA and changes on every release.
      def role_slot(service:, role:, destination:, host:, reports_by_host:)
        prefix = [ service, role, destination.name ].compact.join("-") + "-"
        match = reports_by_host.fetch(host).containers.find { |container| container[:name]&.start_with?(prefix) }

        observed_container(kind: :app, label: role, host: host, match: match, prefix: prefix)
      end

      # Accessories have no destination segment and, unlike roles, we don't know which of the
      # destination's hosts they run on (the scanner only ever captured accessory_names) — so we
      # look for one exact-name match across every host this destination touches.
      def accessory_slot(service:, accessory_name:, destination:, reports_by_host:)
        name = "#{service}-#{accessory_name}"

        reports_by_host.each do |host, report|
          match = report.containers.find { |container| container[:name] == name }
          return observed_container(kind: :accessory, label: accessory_name, host: host, match: match) if match
        end

        observed_container(kind: :accessory, label: accessory_name, host: destination.server_ips.first, match: nil)
      end

      def proxy_slot(host:, reports_by_host:)
        match = reports_by_host.fetch(host).containers.find { |container| container[:name] == "kamal-proxy" }
        observed_container(kind: :proxy, label: "kamal-proxy", host: host, match: match)
      end

      def observed_container(kind:, label:, host:, match:, prefix: nil)
        return ObservedContainer.new(name: nil, kind: kind, label: label, host: host, state: :absent,
                                      status_text: nil, image: nil, version: nil) unless match

        ObservedContainer.new(
          name: match[:name],
          kind: kind,
          label: label,
          host: host,
          state: match[:state].to_s.downcase.to_sym,
          status_text: match[:status_text],
          image: match[:image],
          version: prefix && match[:name].delete_prefix(prefix)
        )
      end

      # kamal-proxy is informational only — it never gates the destination's state.
      def calculate_state(containers)
        gating = containers.reject { |container| container.kind == :proxy }
        return :down if gating.empty?

        if gating.all? { |container| container.state == :running }
          :running
        elsif gating.any? { |container| container.state == :running }
          :partial
        else
          :down
        end
      end
    end
  end
end
