module OperationsHelper
  # Deliberately separate from ManagedAppsHelper::STATUS_COLORS — "running" means
  # something different for an in-flight operation (amber, still working) than
  # for a healthy destination (emerald, all good), so the two enums can't share
  # a palette without lying about one of them.
  STATUS_COLORS = {
    "queued" => "bg-neutral-600",
    "running" => "bg-amber-500",
    "succeeded" => "bg-emerald-500",
    "failed" => "bg-red-600"
  }.freeze

  def operation_status_color(status)
    STATUS_COLORS.fetch(status.to_s, "bg-neutral-600")
  end

  def operation_status_label(status)
    status.to_s.humanize
  end
end
