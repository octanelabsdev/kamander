class ManagedAppsController < ApplicationController
  before_action :set_managed_app, only: %i[show update destroy]

  def index
    @managed_apps = ManagedApp.managed.ordered.includes(:app_destinations)
  end

  def show
  end

  def confirm
    managed_apps = ManagedApp.where(id: Array(params[:managed_app_ids]))
    status = params[:commit] == "hide" ? :hidden : :managed

    ActiveRecord::Base.transaction do
      managed_apps.each do |managed_app|
        managed_app.display_name = label_for(managed_app).presence || managed_app.display_name
        managed_app.update!(status: status)
      end
    end

    redirect_to status == :hidden ? scan_path : root_path, notice: confirm_notice(status, managed_apps.size)
  end

  def update
    @managed_app.update!(managed_app_params)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(@managed_app, partial: "managed_apps/app_card",
          locals: { managed_app: @managed_app })
      end
      format.html { redirect_to @managed_app, notice: "Renamed to #{@managed_app.display_label}." }
    end
  end

  def destroy
    @managed_app.destroy!
    redirect_to root_path, notice: "#{@managed_app.display_label} forgotten."
  end

  private

    def set_managed_app
      @managed_app = ManagedApp.find(params[:id])
    end

    def managed_app_params
      params.require(:managed_app).permit(:display_name)
    end

    # Read one known key at a time out of the labels hash and assign it to
    # one known attribute — safe without a blanket #permit! since nothing
    # here mass-assigns the raw hash to a model.
    def label_for(managed_app)
      params.dig(:labels, managed_app.id.to_s)
    end

    def confirm_notice(status, count)
      noun = "app".pluralize(count)
      status == :hidden ? "#{count} #{noun} hidden." : "#{count} #{noun} added to the dashboard."
    end
end
