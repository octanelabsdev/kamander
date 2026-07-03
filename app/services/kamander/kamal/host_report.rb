module Kamander
  module Kamal
    HostReport = Data.define(:host, :user, :reachable, :containers, :error) do
      def reachable?
        reachable
      end
    end
  end
end
