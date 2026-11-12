class AddCiNameToManagedApps < ActiveRecord::Migration[8.1]
  def change
    add_column :managed_apps, :ci_name, :string
  end
end
