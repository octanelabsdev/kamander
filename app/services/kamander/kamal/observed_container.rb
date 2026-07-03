module Kamander
  module Kamal
    ObservedContainer = Data.define(:name, :kind, :label, :host, :state, :status_text, :image, :version) do
      def absent?
        state == :absent
      end
    end
  end
end
