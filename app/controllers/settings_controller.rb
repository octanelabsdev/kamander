class SettingsController < ApplicationController
  def edit
    @setting = Setting.current
  end

  def update
    Setting.current.update!(setting_params)
    redirect_to edit_setting_path, notice: "Settings updated."
  end

  private

    def setting_params
      params.require(:setting).permit(:scan_root, :default_ssh_user)
    end
end
