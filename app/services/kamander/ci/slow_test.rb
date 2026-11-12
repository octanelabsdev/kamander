module Kamander
  module Ci
    SlowTest = Data.define(:step, :test, :seconds, :file, :line) do
      # "CheckoutTest#test_a_guest_pays" reads as "a guest pays"; the file already names the class.
      def description
        test.to_s.split("#", 2).last.delete_prefix("test_").tr("_", " ")
      end
    end
  end
end
