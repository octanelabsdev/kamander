class CreateManagedApps < ActiveRecord::Migration[8.1]
  def change
    create_table :managed_apps do |t|
      t.string   :repo_path,       null: false
      t.string   :service_name,    null: false
      t.string   :display_name
      t.integer  :status,          null: false, default: 0
      t.integer  :position,        null: false, default: 0
      t.string   :proxy_host                                 # base deploy.yml proxy.host; nil for multi-destination apps
      t.datetime :discovered_at,   null: false
      t.datetime :last_scanned_at, null: false
      t.timestamps
    end
    add_index :managed_apps, :repo_path, unique: true
    add_index :managed_apps, [ :status, :position ]
  end
end
