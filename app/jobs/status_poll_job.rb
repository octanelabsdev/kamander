# Recurring (config/recurring.yml, every 30s) fleet-wide status poll, also
# triggered on demand by "Refresh" scoped to a single app. limits_concurrency
# ensures a slow poll never overlaps the next scheduled tick.
class StatusPollJob < ApplicationJob
  limits_concurrency to: 1, key: "status_poll"

  def perform(managed_app_id: nil)
    reports = Kamander::Kamal::StatusReader.new(destinations: scope(managed_app_id), ssh_client: Kamander::Kamal.ssh_client).call
    Kamander::Kamal::StatusWriter.new(reports).call
  end

  private

  def scope(managed_app_id)
    destinations = AppDestination.includes(:managed_app)
    managed_app_id ? destinations.where(managed_app_id: managed_app_id) : destinations.where(managed_app: ManagedApp.managed)
  end
end
