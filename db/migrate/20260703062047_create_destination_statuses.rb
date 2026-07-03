class CreateDestinationStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :destination_statuses do |t|
      t.references :app_destination, null: false, foreign_key: true, index: { unique: true }
      t.integer  :state,      null: false, default: 0
      t.datetime :checked_at
      t.json     :containers, null: false, default: []
      t.string   :error
      t.timestamps
    end
  end
end
