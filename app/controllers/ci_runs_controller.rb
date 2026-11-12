# Reads ci-box run records off the CI box over SSH; nothing is stored, the
# box's records are the source of truth. No auth, like the rest of the app.
class CiRunsController < ApplicationController
  before_action :require_ci_host

  def index
    @app = params[:app].presence
    @apps = ManagedApp.where.not(ci_name: nil).distinct.order(:ci_name).pluck(:ci_name)
    @listing = run_reader.call(app: @app)
  end

  # The dashboard's Latest CI strip: each managed app's newest run, loaded on
  # click into a frame so the 30-second card broadcasts never touch the box.
  def latest
    @ci_names = ManagedApp.managed.where.not(ci_name: nil).distinct.order(:ci_name).pluck(:ci_name)
    @listing = run_reader.call
    @latest_runs = @listing.runs.group_by(&:app).transform_values(&:first)
  end

  def show
    @listing = run_reader.find(params[:id])
    @run = @listing.runs.first
    return head :not_found if @listing.success? && @run.nil?

    return unless @run

    @log = run_reader.log(@run.id)
    CiFollowJob.perform_later(@run.id) if @run.live?
  end

  private

    def require_ci_host
      redirect_to edit_setting_path, alert: "Set a CI host to use the CI panel." if Setting.current.ci_host.nil?
    end

    def run_reader
      setting = Setting.current
      @run_reader ||= Kamander::Ci::RunReader.new(host: setting.ci_host, user: setting.ci_user)
    end
end
