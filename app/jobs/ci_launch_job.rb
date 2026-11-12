# No retries: a second remote-ci would start a second run.
class CiLaunchJob < ApplicationJob
  queue_as :ci

  discard_on StandardError, report: true do |job, error|
    launch = job.arguments.first
    launch.update!(status: :failed, output: "#{launch.output}kamander: #{error.message}\n")
  end

  def perform(launch)
    setting = Setting.current
    Kamander::Ci::Launcher.new(launch: launch, host: setting.ci_host, user: setting.ci_user).call
  end
end
