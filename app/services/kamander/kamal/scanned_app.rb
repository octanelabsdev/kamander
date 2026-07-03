module Kamander
  module Kamal
    ScannedApp = Data.define(:repo_path, :service_name, :destinations, :error) do
      def error?
        error.present?
      end
    end
  end
end
