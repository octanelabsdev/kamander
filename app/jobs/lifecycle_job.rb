# Runs one Operation to completion. Its own queue (not :default, where the
# 30s status poll lives) — a slow kamal boot streaming for minutes must never
# delay the fleet poll behind it.
#
# No retry_on: re-running a lifecycle verb blind, without knowing what state
# it left the destination in, is dangerous — a failed kamal/ssh command
# already comes back as a normal failed Operation (that's Lifecycle's job,
# not an exception). An actual raise here means Lifecycle itself broke, which
# is a bug, not something to retry. discard_on marks the operation failed
# and frees the destination lock (the partial unique index only excludes
# queued/running) instead of leaving it stuck running forever because a
# crashed job never reached Lifecycle's own terminal-state bookkeeping.
class LifecycleJob < ApplicationJob
  queue_as :lifecycle

  discard_on StandardError, report: true do |job, error|
    operation = job.arguments.first
    operation.update!(status: :failed, output: "#{operation.output}kamander: #{error.message}\n", finished_at: Time.current)
  end

  def perform(operation)
    Kamander::Kamal::Lifecycle.new(operation: operation).call
  end
end
