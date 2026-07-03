module ManagedAppsHelper
  STATUS_COLORS = {
    "unknown" => "bg-neutral-600",
    "running" => "bg-emerald-500",
    "partial" => "bg-amber-500",
    "down" => "bg-red-600",
    "unreachable" => "bg-red-800"
  }.freeze

  STATUS_LABELS = {
    "unknown" => "not yet checked",
    "running" => "Running",
    "partial" => "Partial",
    "down" => "Down",
    "unreachable" => "Unreachable"
  }.freeze

  CONTAINER_COLORS = {
    "running" => "bg-emerald-500",
    "created" => "bg-amber-500",
    "restarting" => "bg-amber-500",
    "paused" => "bg-amber-500",
    "exited" => "bg-red-600",
    "dead" => "bg-red-600",
    "absent" => "bg-neutral-600"
  }.freeze

  def status_dot_color(state)
    STATUS_COLORS.fetch(state.to_s, "bg-neutral-600")
  end

  def status_label(state)
    STATUS_LABELS.fetch(state.to_s, state.to_s.humanize)
  end

  def container_state_color(state)
    CONTAINER_COLORS.fetch(state.to_s, "bg-neutral-600")
  end

  # "as of Ns ago"; nil checked_at (never polled) reads as "not yet checked";
  # past the poll's staleness window gets flagged rather than silently shown.
  def staleness_in_words(checked_at)
    return "not yet checked" if checked_at.nil?

    words = "as of #{seconds_in_words(Time.current - checked_at)} ago"
    checked_at < DestinationStatus::STALE_AFTER.ago ? "#{words} — may be stale" : words
  end

  # 12 chars is enough to eyeball two SHAs apart; full value always lives in the title attr.
  def short_sha(version)
    return nil if version.blank?

    tag.span(version.first(12), title: version, class: "font-mono")
  end

  # An app is only as fresh as its stalest destination.
  def managed_app_checked_at(managed_app)
    managed_app.app_destinations.filter_map { |destination| destination.destination_status&.checked_at }.min
  end

  def deployed_versions(status)
    containers_by(status, kind: "app").select { |container| container["state"] == "running" }
      .filter_map { |container| container["version"] }.uniq
  end

  # "web ✓" for a single-role destination, "2/3 up" for multi-role — a glance-level
  # echo of the reader's per-role slot-up logic, not the raw container list.
  def role_summary(destination)
    status = destination.destination_status
    return nil if status.nil? || status.unreachable?

    roles = destination.servers.keys
    return nil if roles.empty?

    up_roles = roles.select { |role| containers_by(status, kind: "app", role: role).any? { |container| container["state"] == "running" } }

    roles.one? ? "#{roles.first} #{up_roles.any? ? "✓" : "✗"}" : "#{up_roles.size}/#{roles.size} up"
  end

  # Shared filter over a DestinationStatus's containers JSON (string-keyed) —
  # backs the server matrix, accessories, proxy, and unattributed sections alike.
  def containers_by(status, kind:, role: nil, host: nil)
    return [] if status.nil?

    status.containers.select do |container|
      container["kind"] == kind &&
        (role.nil? || container["role"] == role) &&
        (host.nil? || container["host"] == host)
    end
  end

  def accessory_container(status, app_destination, accessory_name)
    expected_service = "#{app_destination.effective_service}-#{accessory_name}"
    containers_by(status, kind: "accessory").find { |container| container["service"] == expected_service } ||
      { "state" => "absent", "status_text" => nil, "version" => nil }
  end

  private

    def seconds_in_words(elapsed)
      seconds = elapsed.round
      seconds < 60 ? "#{seconds}s" : "#{seconds / 60}m"
    end
end
