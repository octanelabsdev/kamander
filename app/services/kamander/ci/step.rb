module Kamander
  module Ci
    Step = Data.define(:name, :result, :took, :seconds) do
      def passed?
        result == "passed"
      end
    end
  end
end
