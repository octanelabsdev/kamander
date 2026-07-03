module Kamander
  module Kamal
    ObservedContainer = Data.define(:name, :service, :role, :destination, :kind, :host, :state, :status_text, :image, :version) do
      def absent?
        state == :absent
      end
    end
  end
end
