module Kamander
  module Kamal
    CommandResult = Data.define(:exit_status, :success) do
      def success?
        success
      end
    end
  end
end
