class ManagedApp < ApplicationRecord
  enum :status, { discovered: 0, managed: 1, hidden: 2 }

  has_many :app_destinations, dependent: :destroy

  validates :repo_path, presence: true, uniqueness: true
  validates :service_name, presence: true

  scope :ordered, -> { order(:position, :service_name) }

  def display_label
    display_name.presence || service_name
  end
end
