module BoxHealthsHelper
  def box_health_stat(label, value, note: nil, warn: false, &block)
    tag.div class: "rounded-md border px-3 py-2 #{warn ? "border-amber-700 bg-amber-950/30" : "border-neutral-800"}", data: { stat: label } do
      safe_join([
        tag.dt(label, class: "text-xs text-neutral-500"),
        tag.dd(block ? capture(&block) : (value || tag.span("unknown", class: "italic text-neutral-600")),
          class: "mt-0.5 tabular-nums #{warn ? "text-amber-300" : "text-neutral-200"}"),
        (tag.dd(note, class: "text-xs text-neutral-500") if note)
      ])
    end
  end

  def box_health_percent(ratio)
    number_to_percentage(ratio * 100, precision: 0) if ratio
  end
end
