# The sha comes from the form, so a real run signs the commit Evan confirmed or nothing.
class CiLaunchesController < ApplicationController
  def create
    managed_app = ManagedApp.managed.where.not(ci_name: nil).find(params[:managed_app_id])
    launch = managed_app.ci_launches.create!(launch_params)
    CiLaunchJob.perform_later(launch)
    redirect_to launch
  rescue ActiveRecord::RecordNotUnique
    redirect_back fallback_location: managed_app, alert: "CI is already starting for #{managed_app.display_label}."
  end

  def show
    @launch = CiLaunch.find(params[:id])
    redirect_to ci_run_path(@launch.run_id) if @launch.started?
  end

  private

    def launch_params
      { sha: params.require(:sha), branch: params[:branch], dry_run: params[:dry_run] != "0" }
    end
end
