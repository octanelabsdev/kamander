# No auth by design (127.0.0.1, single-user) — same as the rest of the app.
class StatusRefreshesController < ApplicationController
  def create
    if params[:managed_app_id].present?
      managed_app = ManagedApp.managed.find(params[:managed_app_id])
      StatusPollJob.perform_later(managed_app_id: managed_app.id)
    else
      StatusPollJob.perform_later
    end

    redirect_back fallback_location: root_path, notice: "Status refresh queued."
  end
end
