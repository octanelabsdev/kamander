# Separate from ManagedAppsController on purpose: like ScansController and
# StatusRefreshesController, this orchestrates a Kamander::Kamal service
# against live infrastructure (docker stats over SSH) rather than doing CRUD
# on a ManagedApp — same category as OperationsController, not as #confirm.
# No auth by design (127.0.0.1, single-user) — same as the rest of the app.
class ResourceUsagesController < ApplicationController
  def show
    managed_app = ManagedApp.managed.find(params[:id])
    container_metrics = Kamander::Kamal::MetricsReader.new(managed_app: managed_app).call

    render partial: "managed_apps/metrics", layout: false,
      locals: { managed_app: managed_app, container_metrics: container_metrics }
  end
end
