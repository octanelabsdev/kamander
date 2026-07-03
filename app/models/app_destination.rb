class AppDestination < ApplicationRecord
  belongs_to :managed_app

  validates :config_file, presence: true, uniqueness: { scope: :managed_app_id }

  def server_ips
    servers.values.flatten.uniq
  end

  def base?
    name.nil?
  end
end
