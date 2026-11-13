# Holds a ci-lane thread for the whole run; past the hour lock a second viewer may start a duplicate follower.
class CiFollowJob < ApplicationJob
  queue_as :ci
  limits_concurrency key: ->(run_id) { run_id }, duration: 1.hour, on_conflict: :discard

  def perform(run_id)
    setting = Setting.current
    run = Kamander::Ci::RunReader.new(host: setting.ci_host, user: setting.ci_user).find(run_id).runs.first
    Kamander::Ci::LogFollower.new(run: run, host: setting.ci_host, user: setting.ci_user).call if run
  end
end
