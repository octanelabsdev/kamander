# The CI box's health, read on click into a frame: one SSH call, nothing stored.
class BoxHealthsController < ApplicationController
  def show
    setting = Setting.current
    return redirect_to edit_setting_path if setting.ci_host.nil?

    @host = setting.ci_host
    @health = Kamander::Ci::BoxHealth.new(host: setting.ci_host, user: setting.ci_user).call
  end
end
