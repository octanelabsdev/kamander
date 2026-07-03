module Kamander
  module Kamal
    DestinationReport = Data.define(:app_destination_id, :state, :containers, :error, :checked_at) do
      def error?
        error.present?
      end
    end
  end
end
