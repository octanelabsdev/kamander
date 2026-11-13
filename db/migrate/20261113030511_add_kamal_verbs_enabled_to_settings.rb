class AddKamalVerbsEnabledToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :kamal_verbs_enabled, :boolean, default: true, null: false
  end
end
