module Kamander
  module Kamal
    # Reads live container status for a set of AppDestinations. Unit of work is
    # the (host, ssh_user) pair, not the destination — hosts running several
    # apps get exactly one SSH + one `docker ps` between them. Never persists
    # anything (that's StatusWriter); a dead host isolates to the destinations
    # that need it and never blocks the rest of the batch.
    #
    # AMENDMENT 2: matching is label-driven (kamal's own service/role/destination
    # container labels), not name-prefix — the fleet has plain deploys (empty
    # destination label) and per-destination service overrides that prefix
    # matching can't tell apart. Name-prefix is kept only as a fallback for
    # containers with no labels at all.
    class StatusReader
      DOCKER_PS_COMMAND = "docker ps --all --no-trunc --format '{{json .}}'"

      def initialize(destinations:, ssh_client: SshClient.new)
        @destinations = destinations
        @ssh_client = ssh_client
      end

      def call
        host_reports = fetch_host_reports
        checked_at = Time.current

        reports = @destinations.map { |destination| build_report(destination, host_reports, checked_at) }
        attach_unattributed_containers(reports, host_reports)
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
          { name: raw["Names"], state: raw["State"], status_text: raw["Status"], image: raw["Image"], labels: parse_labels(raw["Labels"]) }
        rescue JSON::ParserError
          nil
        end
      end

      def parse_labels(labels_string)
        labels_string.to_s.split(",").filter_map do |pair|
          key, value = pair.split("=", 2)
          [ key, value.to_s ] if key.present?
        end.to_h
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
        role_slots = destination.servers.flat_map do |role, ips|
          ips.flat_map { |host| role_slot(destination, role, host, reports_by_host) }
        end

        accessory_slots = destination.accessory_names.map { |accessory_name| accessory_slot(destination, accessory_name, reports_by_host) }

        proxy_slots = reports_by_host.keys.map { |host| proxy_slot(host, reports_by_host) }

        role_slots + accessory_slots + proxy_slots
      end

      # A role slot can carry more than one live container mid-deploy (old version draining
      # alongside the new one) or with replicas — every attributing container is surfaced with
      # its own version, never collapsed to a single match. Absent only when there are none.
      def role_slot(destination, role, host, reports_by_host)
        matches = find_role_containers(destination, role, host, reports_by_host)
        return [ observed_container(kind: :app, host: host, service: destination.effective_service, role: role,
                                     destination: destination.name, match: nil) ] if matches.empty?

        matches.map do |match|
          observed_container(kind: :app, host: host, service: destination.effective_service, role: role,
                              destination: destination.name, match: match)
        end
      end

      def find_role_containers(destination, role, host, reports_by_host)
        containers = reports_by_host.fetch(host).containers

        labeled_matches = containers.select do |container|
          classify(container) == :app &&
            container[:labels]["role"] == role &&
            attribute_destination(container) == destination
        end
        return labeled_matches if labeled_matches.any?

        # Ground truth (kamal configuration/role.rb): container_prefix = [service, role, destination].compact.join("-").
        # Fallback only — real kamal deploys always carry labels; this covers containers that predate them.
        prefix = [ destination.effective_service, role, destination.name ].compact.join("-") + "-"
        containers.select { |container| container[:labels].blank? && container[:name]&.start_with?(prefix) }
      end

      # Accessories have no destination segment and, unlike roles, we don't know which of the
      # destination's hosts they run on (the scanner only ever captured accessory_names) — so we
      # look for one match across every host this destination touches.
      def accessory_slot(destination, accessory_name, reports_by_host)
        expected_service = "#{destination.effective_service}-#{accessory_name}"

        reports_by_host.each do |host, report|
          match = report.containers.find do |container|
            classify(container) == :accessory &&
              (container[:labels]["service"] == expected_service ||
               (container[:labels].blank? && container[:name] == expected_service))
          end
          return observed_container(kind: :accessory, host: host, service: expected_service, role: nil,
                                     destination: destination.name, match: match) if match
        end

        observed_container(kind: :accessory, host: destination.server_ips.first, service: expected_service, role: nil,
                            destination: destination.name, match: nil)
      end

      def proxy_slot(host, reports_by_host)
        match = reports_by_host.fetch(host).containers.find { |container| container[:name] == "kamal-proxy" }
        observed_container(kind: :proxy, host: host, service: nil, role: nil, destination: nil, match: match)
      end

      # A container is only ever :app if kamal actually labeled it with a role — everything else
      # (accessories, foreign containers) falls through so accessory matching can take a look.
      def classify(container)
        return :proxy if container[:name] == "kamal-proxy"

        container[:labels]["role"].present? ? :app : :accessory
      end

      # AMENDMENT 2 app attribution: (1) a non-empty destination label pins the exact AppDestination;
      # (2) an empty destination label (plain `kamal deploy`, no -d) falls back to the base destination
      # (name nil) for that service, then the sole destination with that service — anything left over
      # is genuinely ambiguous or unknown and surfaces as unattributed instead of being guessed at.
      def attribute_destination(container)
        service = container[:labels]["service"]
        return nil if service.blank?

        destination_label = container[:labels]["destination"]

        if destination_label.present?
          @destinations.find { |d| d.effective_service == service && d.name == destination_label }
        else
          same_service = @destinations.select { |d| d.effective_service == service }
          same_service.find(&:base?) || (same_service.first if same_service.one?)
        end
      end

      def observed_container(kind:, host:, service:, role:, destination:, match:)
        return ObservedContainer.new(name: nil, service: service, role: role, destination: destination, kind: kind,
                                      host: host, state: :absent, status_text: nil, image: nil, version: nil) unless match

        ObservedContainer.new(
          name: match[:name],
          service: service,
          role: role,
          destination: destination,
          kind: kind,
          host: host,
          state: match[:state].to_s.downcase.to_sym,
          status_text: match[:status_text],
          image: match[:image],
          version: version_from_image(match[:image])
        )
      end

      def version_from_image(image)
        image.to_s.split(":").last
      end

      # kamal-proxy is informational only and unattributed containers aren't expected slots at all —
      # neither ever gates the destination's state. A role slot can hold more than one container
      # mid-deploy (see role_slot) — it counts as running if ANY of them is, so a draining old
      # version alongside a healthy new one reads as running, not partial.
      def calculate_state(containers)
        gating = containers.reject { |container| container.kind == :proxy || container.kind == :unattributed }
        return :down if gating.empty?

        slot_states = gating.group_by { |container| [ container.kind, container.role, container.host, container.service ] }
          .values.map { |slot| slot.any? { |container| container.state == :running } ? :running : :down }

        if slot_states.all? { |state| state == :running }
          :running
        elsif slot_states.any? { |state| state == :running }
          :partial
        else
          :down
        end
      end

      # Containers we can't attribute to any destination are never dropped — they surface on every
      # destination report sharing the host they were seen on, so an operator investigating any app
      # there sees "something's running here I don't recognize" instead of silence.
      def attach_unattributed_containers(reports, host_reports)
        extra = Hash.new { |hash, key| hash[key] = [] }

        host_reports.each do |(host, _user), host_report|
          next unless host_report.reachable?

          orphans = host_report.containers.select { |container| classify(container) == :app && attribute_destination(container).nil? }
          next if orphans.empty?

          @destinations.select { |destination| destination.server_ips.include?(host) }.each do |destination|
            orphans.each do |container|
              extra[destination.id] << observed_container(kind: :unattributed, host: host,
                service: container[:labels]["service"], role: container[:labels]["role"],
                destination: container[:labels]["destination"], match: container)
            end
          end
        end

        reports.map do |report|
          additions = extra[report.app_destination_id]
          additions.empty? || report.state == :unreachable ? report : report.with(containers: report.containers + additions)
        end
      end
    end
  end
end
