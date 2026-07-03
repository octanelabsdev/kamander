class CreateOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :operations do |t|
      t.references :managed_app,     null: false, foreign_key: true
      t.references :app_destination, null: false, foreign_key: true
      t.integer  :verb,        null: false
      t.integer  :status,      null: false, default: 0   # 0 = queued, 1 = running — the partial unique index below depends on these values
      t.text     :output,      null: false, default: ""
      t.string   :command,     null: false
      t.string   :version
      t.integer  :exit_status
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :operations, [ :managed_app_id, :created_at ]
    add_index :operations, [ :app_destination_id, :status ]
    add_index :operations, :app_destination_id, unique: true,
              where: "status IN (0, 1)", name: "index_operations_one_active_per_destination"
  end
end
