class AddCiHostAndCiUserToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :ci_host, :string, default: "legion"
    add_column :settings, :ci_user, :string, default: "ci", null: false
  end
end
