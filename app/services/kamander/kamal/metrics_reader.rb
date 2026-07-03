module Kamander
  module Kamal
    # On-demand `docker stats` for one app's own known containers — never
    # stored, point-in-time only. Per-host batching like StatusReader: one
    # `docker stats` call per (host, ssh_user) pair, scoped to just the
    # container names running there for THIS app, never a neighbor's.
    class MetricsReader
      DOCKER_STATS_COMMAND = "docker stats --no-stream --format '{{json .}}'"

      # The (name, host) slots this reader will look up metrics for — running
      # app/accessory containers only (kamal-proxy is shared host infrastructure,
      # not this app's; nothing to report on an exited or never-seen container).
      # Public and reused by #call's own host-batching below, so there's exactly
      # one definition of "what counts" — callers that need the full expected
      # set (e.g. a view telling "no data" apart from "nothing running") read
      # it from here instead of re-deriving it.
      def self.expected_containers(managed_app)
        managed_app.app_destinations.flat_map do |destination|
          running_known_containers(destination).map { |container| { name: container["name"], host: container["host"] } }
        end
      end

      def self.running_known_containers(destination)
        containers = destination.destination_status&.containers || []
        containers.select { |container| %w[app accessory].include?(container["kind"]) && container["state"] == "running" }
      end

      def initialize(managed_app:, ssh_client: Kamander::Kamal.ssh_client)
        @managed_app = managed_app
        @ssh_client = ssh_client
      end

      def call
        names_by_host.flat_map { |(host, user), names| fetch_metrics(host, user, names) }
      end

      private

      def names_by_host
        grouped = Hash.new { |hash, key| hash[key] = [] }

        @managed_app.app_destinations.each do |destination|
          self.class.running_known_containers(destination).each do |container|
            grouped[[ container["host"], destination.effective_ssh_user ]] << container["name"]
          end
        end

        grouped.transform_values(&:uniq)
      end

      # An unreachable host just contributes no metrics for its containers — this
      # data is transient and view-only, so there's no row to flag as errored the
      # way DestinationStatus does for durable state.
      def fetch_metrics(host, user, names)
        result = @ssh_client.capture(host: host, user: user, command: "#{DOCKER_STATS_COMMAND} #{names.join(" ")}")
        return [] unless result.success?

        parse(result.stdout, host: host)
      end

      # Container names are host-independent — a role deployed to N servers uses the
      # same name on each, so host is the only thing that distinguishes their rows.
      def parse(stdout, host:)
        stdout.each_line.filter_map do |line|
          next if line.strip.empty?

          raw = JSON.parse(line)
          mem_usage, mem_limit = raw["MemUsage"].to_s.split(" / ")

          ContainerMetrics.new(
            name: raw["Name"],
            host: host,
            cpu_percent: raw["CPUPerc"],
            mem_usage: mem_usage,
            mem_limit: mem_limit,
            mem_percent: raw["MemPerc"],
            net_io: raw["NetIO"],
            block_io: raw["BlockIO"],
            pids: raw["PIDs"]
          )
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
