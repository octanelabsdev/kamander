class AddPullBeforeScanToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :pull_before_scan, :boolean, default: false, null: false
  end
end
