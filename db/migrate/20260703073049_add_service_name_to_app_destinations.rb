class AddServiceNameToAppDestinations < ActiveRecord::Migration[8.1]
  def up
    add_column :app_destinations, :service_name, :string

    execute <<~SQL
      UPDATE app_destinations
      SET service_name = (
        SELECT managed_apps.service_name
        FROM managed_apps
        WHERE managed_apps.id = app_destinations.managed_app_id
      )
    SQL

    change_column_null :app_destinations, :service_name, false
  end

  def down
    remove_column :app_destinations, :service_name
  end
end
