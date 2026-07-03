class AppDestination < ApplicationRecord
  belongs_to :managed_app
  has_one :destination_status, dependent: :destroy

  validates :config_file, presence: true, uniqueness: { scope: :managed_app_id }

  def server_ips
    servers.values.flatten.uniq
  end

  def base?
    name.nil?
  end

  def effective_ssh_user
    ssh_user.presence || Setting.current.default_ssh_user
  end
end
