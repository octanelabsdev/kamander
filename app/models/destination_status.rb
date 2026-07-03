class DestinationStatus < ApplicationRecord
  STALE_AFTER = 90.seconds

  enum :state, { unknown: 0, running: 1, partial: 2, down: 3, unreachable: 4 }

  belongs_to :app_destination

  def stale?
    checked_at.nil? || checked_at < STALE_AFTER.ago
  end
end
