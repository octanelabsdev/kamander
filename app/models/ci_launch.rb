# One Run CI click, kept so a fast refusal isn't lost; the run itself lives only on the box.
class CiLaunch < ApplicationRecord
  enum :status, { queued: 0, started: 1, failed: 2 }

  belongs_to :managed_app

  broadcasts_refreshes

  validates :sha, presence: true

  def short_sha
    sha.first(7)
  end
end
