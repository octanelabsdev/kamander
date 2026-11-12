class CreateCiLaunches < ActiveRecord::Migration[8.1]
  def change
    create_table :ci_launches do |t|
      t.references :managed_app, null: false, foreign_key: true
      t.string :sha, null: false
      t.string :branch
      t.boolean :dry_run, null: false, default: true
      t.integer :status, null: false, default: 0
      t.text :output, null: false, default: ""
      t.string :run_id
      t.timestamps
    end
    # status 0 is queued: one launch in flight per app, so a double click can't start two runs.
    add_index :ci_launches, :managed_app_id, unique: true, where: "status = 0",
              name: "index_ci_launches_one_queued_per_app"
  end
end
