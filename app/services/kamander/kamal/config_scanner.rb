module Kamander
  module Kamal
    # Reads deploy.yml (and any deploy.<destination>.yml overlays) under each
    # repo in scan_root and returns ScannedApp value objects. Never raises —
    # a repo we can't read or parse comes back with its error field set so
    # the scan can continue past it.
    class ConfigScanner
      class ParseError < StandardError; end

      def initialize(scan_root:)
        @scan_root = scan_root
      end

      def call
        Dir.glob(File.join(@scan_root, "*", "config", "deploy.yml")).sort.filter_map { |path| scan_repo(path) }
      end

      private

      def scan_repo(base_path)
        repo_path = File.dirname(File.dirname(base_path))
        base_config = load_config(base_path)
        return nil unless base_config.is_a?(Hash)

        service_name = base_config["service"]

        ScannedApp.new(
          repo_path: repo_path,
          service_name: service_name,
          destinations: build_destinations(base_path, base_config),
          error: service_name.present? ? nil : "missing service name"
        )
      rescue ParseError => e
        ScannedApp.new(repo_path: repo_path, service_name: nil, destinations: [], error: e.message)
      end

      def build_destinations(base_path, base_config)
        overlay_paths = find_overlays(base_path)
        return [ extract_destination(name: nil, config_file: File.basename(base_path), config: base_config) ] if overlay_paths.empty?

        overlay_paths.map { |overlay_path| build_overlay_destination(base_config, overlay_path) }
      end

      def find_overlays(base_path)
        Dir.glob(File.join(File.dirname(base_path), "deploy.*.yml")).sort
      end

      def build_overlay_destination(base_config, overlay_path)
        name = overlay_name(overlay_path)
        config_file = File.basename(overlay_path)
        overlay_config = load_config(overlay_path)
        overlay_config = {} unless overlay_config.is_a?(Hash)
        merged = base_config.deep_merge(overlay_config)

        extract_destination(name: name, config_file: config_file, config: merged)
      rescue ParseError => e
        ScannedDestination.new(name: name, config_file: config_file, servers: {}, accessory_names: [],
                                ssh_user: nil, proxy_host: nil, error: e.message)
      end

      def overlay_name(overlay_path)
        File.basename(overlay_path, ".yml").delete_prefix("deploy.")
      end

      def extract_destination(name:, config_file:, config:)
        ScannedDestination.new(
          name: name,
          config_file: config_file,
          servers: normalize_servers(config["servers"]),
          accessory_names: (config["accessories"] || {}).keys,
          ssh_user: config.dig("ssh", "user"),
          proxy_host: config.dig("proxy", "host"),
          error: nil
        )
      end

      def normalize_servers(servers_config)
        case servers_config
        when Array
          { "web" => servers_config }
        when Hash
          servers_config.transform_values { |value| value.is_a?(Hash) ? Array(value["hosts"]) : Array(value) }
        else
          {}
        end
      end

      def load_config(path)
        load_yaml(render_erb(File.read(path)))
      rescue Errno::ENOENT, Errno::EACCES, IOError => e
        raise ParseError, "could not read #{path}: #{e.message}"
      rescue SyntaxError, StandardError => e
        raise ParseError, "could not parse #{path}: #{e.message}"
      end

      def render_erb(source)
        ERB.new(source).result(clean_binding)
      end

      def load_yaml(rendered)
        YAML.safe_load(rendered, aliases: true)
      end

      # A fresh anonymous object per render — keeps the scanner's own ivars/methods
      # out of ERB's reach and avoids leaking local vars between files.
      def clean_binding
        Object.new.instance_eval { binding }
      end
    end
  end
end
