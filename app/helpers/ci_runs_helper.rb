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

  # One thin segment per step, green or red; hover a segment for its name.
  def ci_step_bar(run)
    tag.div class: "relative z-10 flex h-1.5 w-full max-w-64 gap-px overflow-hidden rounded-full bg-neutral-800" do
      safe_join(run.steps.map do |step|
        tag.span class: "flex-1 #{step.passed? ? "bg-emerald-500/70" : "bg-red-500"}",
          title: [ step.name, step.took ].compact.join(" · "), data: { step: step.name }
      end)
    end
  end

  def ci_step_summary(run)
    if (step = run.failed_step)
      tag.span "Failed at #{step.name}", class: "truncate text-red-400", data: { step_result: step.result }, title: step.name
    elsif run.status == "queued"
      tag.span "Waiting for the box", class: "text-neutral-500"
    elsif run.live?
      tag.span "#{pluralize(run.steps.size, "step")} done", class: "text-sky-400"
    else
      tag.span "#{run.steps.size}/#{run.steps.size} steps", class: "text-neutral-500"
    end
  end

  # "9m ago", with the exact time on hover.
  def ci_ago(time)
    return "—" unless time

    seconds = (Time.current - time).to_i
    words = if seconds < 60 then "just now"
    elsif seconds < 3600 then "#{seconds / 60}m ago"
    elsif seconds < 86_400 then "#{seconds / 3600}h ago"
    else "#{seconds / 86_400}d ago"
    end
    time_tag time, words, title: l(time.localtime, format: :long)
  end

  def ci_duration(seconds)
    return "—" if seconds.nil?

    minutes, secs = seconds.divmod(60)
    minutes.zero? ? "#{secs}s" : "#{minutes}m #{secs}s"
  end
end
