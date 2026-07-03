class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :scan_root,        null: false, default: "~/Development"
      t.string :default_ssh_user, null: false, default: "deploy"
      t.timestamps
    end
  end
end
