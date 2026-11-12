# Follows one live CI run's log for as long as the run lasts, so it gets its
# own `ci` lane: a long bin/ci must never hold a thread the fleet poll or a
# lifecycle operation needs. Every viewer of a live run enqueues one, and
# all but the first are discarded. If a run outlasts the hour the lock
# lapses, and a viewer arriving after that starts a second follower whose
# lines show up twice until the closing refresh.
class CiFollowJob < ApplicationJob
  queue_as :ci
  limits_concurrency key: ->(run_id) { run_id }, duration: 1.hour, on_conflict: :discard

  def perform(run_id)
    setting = Setting.current
    run = Kamander::Ci::RunReader.new(host: setting.ci_host, user: setting.ci_user).find(run_id).runs.first
    Kamander::Ci::LogFollower.new(run: run, host: setting.ci_host, user: setting.ci_user).call if run
  end
end
