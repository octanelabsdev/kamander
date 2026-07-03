module Kamander
  module Kamal
    # Persists DestinationReport structs from StatusReader into DestinationStatus
    # rows — one per destination, overwritten in place on every poll. P2 tracks
    # current state only, not history (that's P3's Operation model).
    class StatusWriter
      def initialize(reports)
        @reports = reports
      end

      def call
        ActiveRecord::Base.transaction do
          @reports.each { |report| write(report) }
        end
      end

      private

      def write(report)
        status = DestinationStatus.find_or_initialize_by(app_destination_id: report.app_destination_id)
        status.update!(
          state: report.state,
          checked_at: report.checked_at,
          error: report.error,
          containers: report.containers.map { |container| serialize(container) }
        )
      end

      # Explicit string-keyed hash rather than container.to_h — matches what the
      # containers JSON column round-trips as, independent of how the json type
      # happens to encode symbol keys/values.
      def serialize(container)
        {
          "name" => container.name,
          "service" => container.service,
          "role" => container.role,
          "destination" => container.destination,
          "kind" => container.kind.to_s,
          "host" => container.host,
          "state" => container.state.to_s,
          "status_text" => container.status_text,
          "image" => container.image,
          "version" => container.version
        }
      end
    end
  end
end
