class AppDestination < ApplicationRecord
  belongs_to :managed_app
  has_one :destination_status, dependent: :destroy
  has_many :operations, dependent: :destroy
  has_one :active_operation, -> { active }, class_name: "Operation"

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

  def effective_service
    service_name.presence || managed_app.service_name
  end
end
