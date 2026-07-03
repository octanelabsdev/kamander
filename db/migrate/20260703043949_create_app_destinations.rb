class CreateAppDestinations < ActiveRecord::Migration[8.1]
  def change
    create_table :app_destinations do |t|
      t.references :managed_app,  null: false, foreign_key: true
      t.string  :name
      t.string  :config_file,     null: false
      t.json    :servers,         null: false, default: {}
      t.json    :accessory_names, null: false, default: []
      t.string  :ssh_user
      t.string  :proxy_host
      t.timestamps
    end
    add_index :app_destinations, [ :managed_app_id, :config_file ], unique: true
    add_index :app_destinations, [ :managed_app_id, :name ]
  end
end
