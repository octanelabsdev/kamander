class ManagedApp < ApplicationRecord
  STATUS_SEVERITY = %w[unknown running partial down unreachable].freeze

  enum :status, { discovered: 0, managed: 1, hidden: 2 }

  has_many :app_destinations, dependent: :destroy
  has_many :destination_statuses, through: :app_destinations
  has_many :operations, dependent: :destroy

  validates :repo_path, presence: true, uniqueness: true
  validates :service_name, presence: true

  scope :ordered, -> { order(:position, :service_name) }

  def display_label
    display_name.presence || service_name
  end

  def status_rollup
    states = app_destinations.map { |destination| destination.destination_status&.state || "unknown" }
    return "unknown" if states.empty?

    states.max_by { |state| STATUS_SEVERITY.index(state) }
  end
end
