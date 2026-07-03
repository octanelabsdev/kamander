module Kamander
  module Kamal
    # Persists ScannedApp/ScannedDestination structs from ConfigScanner into
    # ManagedApp/AppDestination. Apps we couldn't scan cleanly (error? true)
    # are left out of the DB entirely — service_name is required by the
    # schema, and an unscannable app never has one. Those apps surface to the
    # operator straight from the raw scan results, not from what's persisted.
    class ScanImporter
      def initialize(scanned_apps)
        @scanned_apps = scanned_apps
      end

      def call
        ActiveRecord::Base.transaction do
          @scanned_apps.filter_map { |scanned_app| import(scanned_app) }
        end
      end

      private

      def import(scanned_app)
        return if scanned_app.error?

        now = Time.current
        managed_app = ManagedApp.find_or_initialize_by(repo_path: scanned_app.repo_path)
        managed_app.discovered_at = now if managed_app.new_record?
        managed_app.service_name = scanned_app.service_name
        managed_app.proxy_host = base_proxy_host(scanned_app)
        managed_app.last_scanned_at = now
        managed_app.save!

        sync_destinations(managed_app, scanned_app.destinations)
        managed_app
      end

      def base_proxy_host(scanned_app)
        scanned_app.destinations.find { |destination| destination.name.nil? }&.proxy_host
      end

      def sync_destinations(managed_app, scanned_destinations)
        config_files = scanned_destinations.map(&:config_file)
        managed_app.app_destinations.where.not(config_file: config_files).destroy_all

        scanned_destinations.each do |scanned_destination|
          # A transiently broken destination keeps its config_file in the keep-list
          # above (so a rescan glitch doesn't delete it) but is otherwise skipped —
          # its last-known-good cached values survive rather than being clobbered.
          next if scanned_destination.error?

          destination = managed_app.app_destinations.find_or_initialize_by(config_file: scanned_destination.config_file)
          destination.update!(
            name: scanned_destination.name,
            service_name: scanned_destination.service_name,
            servers: scanned_destination.servers,
            accessory_names: scanned_destination.accessory_names,
            ssh_user: scanned_destination.ssh_user,
            proxy_host: scanned_destination.proxy_host
          )
        end
      end
    end
  end
end
