class Operation < ApplicationRecord
  enum :verb, { restart: 0, reboot: 1, stop: 2, start: 3 }
  enum :status, { queued: 0, running: 1, succeeded: 2, failed: 3 }

  belongs_to :managed_app
  belongs_to :app_destination

  validate :app_destination_belongs_to_managed_app

  scope :active, -> { where(status: [ :queued, :running ]) }
  scope :recent, -> { order(created_at: :desc) }

  def duration
    return nil unless started_at && finished_at

    finished_at - started_at
  end

  def terminal?
    succeeded? || failed?
  end

  private

    def app_destination_belongs_to_managed_app
      return if app_destination.nil? || managed_app.nil?
      return if app_destination.managed_app_id == managed_app_id

      errors.add(:app_destination, "must belong to the operation's managed app")
    end
end
