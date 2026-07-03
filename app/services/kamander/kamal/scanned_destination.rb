module Kamander
  module Kamal
    ScannedDestination = Data.define(:name, :config_file, :servers, :accessory_names, :ssh_user, :proxy_host, :error) do
      def error?
        error.present?
      end
    end
  end
end
