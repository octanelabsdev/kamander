class Setting < ApplicationRecord
  def self.current
    first_or_create!
  end

  def expanded_scan_root
    File.expand_path(scan_root)
  end
end
