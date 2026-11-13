# One Run CI click, kept so a fast refusal isn't lost; the run itself lives only on the box.
class CiLaunch < ApplicationRecord
  enum :status, { queued: 0, started: 1, failed: 2 }

  belongs_to :managed_app

  broadcasts_refreshes

  # Longer than Launcher waits for a record, so only a launch whose job died is stale.
  STALE_AFTER = 3.minutes

  validates :sha, presence: true

  def self.give_up_stale
    queued.where(created_at: ...STALE_AFTER.ago).find_each do |launch|
      launch.update!(status: :failed, output: "#{launch.output}kamander: gave up; the launch job stopped without finishing. Check the CI page before starting again.\n")
    end
  end

  def short_sha
    sha.first(7)
  end
end
