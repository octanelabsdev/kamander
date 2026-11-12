class Setting < ApplicationRecord
  normalizes :ci_host, with: ->(host) { host.strip.presence }
  normalizes :ci_user, with: ->(user) { user.strip }

  validates :ci_user, presence: true

  def self.current
    first_or_create!
  end

  def expanded_scan_root
    File.expand_path(scan_root)
  end
end
