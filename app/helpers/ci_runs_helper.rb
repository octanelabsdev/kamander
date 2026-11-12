module CiRunsHelper
  CI_STATE_COLORS = {
    "passed" => "bg-emerald-500",
    "running" => "bg-sky-500",
    "queued" => "bg-neutral-400",
    "failed" => "bg-red-600",
    "error" => "bg-red-800",
    "cancelled" => "bg-amber-500",
    "lost" => "bg-neutral-600"
  }.freeze

  CI_STATE_LABELS = { "lost" => "lost (box restarted?)" }.freeze

  def ci_state_pill(run)
    tag.span class: "inline-flex items-center gap-1.5 rounded-full border border-neutral-700 px-2 py-0.5 text-xs text-neutral-300" do
      safe_join([ tag.span(class: "h-2 w-2 rounded-full #{CI_STATE_COLORS.fetch(run.state, "bg-neutral-600")}"),
                  CI_STATE_LABELS.fetch(run.state, run.state.humanize) ])
    end
  end

  def ci_step_pill(step)
    tag.span class: "rounded px-1.5 py-0.5 text-xs #{step.passed? ? "bg-neutral-800 text-neutral-400" : "bg-red-950 text-red-300"}",
      data: { step_result: step.result }, title: step.took do
      "#{step.passed? ? "✅" : "❌"} #{step.name}"
    end
  end

  def ci_duration(seconds)
    return "—" if seconds.nil?

    minutes, secs = seconds.divmod(60)
    minutes.zero? ? "#{secs}s" : "#{minutes}m #{secs}s"
  end
end
