class DestinationStatus < ApplicationRecord
  STALE_AFTER = 90.seconds

  enum :state, { unknown: 0, running: 1, partial: 2, down: 3, unreachable: 4 }

  belongs_to :app_destination

  # A single after_commit covering both actions — after_create_commit and
  # after_update_commit pointed at the same method name silently collide in
  # ActiveSupport::Callbacks (the later registration wins), so newly created
  # rows never broadcast. Confirmed by direct reproduction; only the merged
  # form fires on both create and update.
  after_commit :broadcast_status, on: %i[create update]

  def stale?
    checked_at.nil? || checked_at < STALE_AFTER.ago
  end

  private

    # Two audiences per write: the dashboard card (anyone with the index
    # open) and this app's own stats page (anyone with its show page open).
    # No-subscriber broadcasts are free, so both fire on every poll/refresh.
    def broadcast_status
      managed_app = app_destination.managed_app

      broadcast_replace_to "managed_apps", target: managed_app,
        partial: "managed_apps/app_card", locals: { managed_app: managed_app }

      broadcast_replace_to [ managed_app, :statuses ], target: [ app_destination, :status ],
        partial: "managed_apps/destination_status", locals: { app_destination: app_destination }
    end
end
