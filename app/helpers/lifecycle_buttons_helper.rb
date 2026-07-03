module LifecycleButtonsHelper
  # Design §5.4 verb transparency — plain-language tooltip per button, distinct
  # from the literal command (the operation console shows that).
  LIFECYCLE_VERBS = {
    "restart" => { label: "Restart",
      tooltip: "Fast restart of the running container, same version, proxy route kept (server-side docker restart)." },
    "reboot" => { label: "Reboot",
      tooltip: "Version-pinned rolling replace via kamal, re-registers with proxy." },
    "stop" => { label: "Stop",
      tooltip: "Stops the app and deregisters from the proxy — causes downtime." },
    "start" => { label: "Start",
      tooltip: "Boots the last-deployed version, pinned." }
  }.freeze

  def lifecycle_verb_label(verb)
    LIFECYCLE_VERBS.fetch(verb.to_s) { { label: verb.to_s.capitalize } }[:label]
  end

  def lifecycle_verb_tooltip(verb)
    LIFECYCLE_VERBS.fetch(verb.to_s) { {} }[:tooltip]
  end

  def lifecycle_button_class(verb)
    base = "rounded-md border px-2 py-1 text-xs font-medium"
    verb.to_s == "stop" ? "#{base} border-red-900 text-red-400 hover:bg-red-950/40" : "#{base} border-neutral-700 text-neutral-300 hover:bg-neutral-800"
  end

  # Names the destination + hosts, per §5.2 — used for both the plain
  # turbo_confirm buttons and the typed-confirm modal's copy.
  def lifecycle_confirm_text(verb, destination)
    "#{lifecycle_verb_label(verb)} #{destination.name || "base"} on #{destination.server_ips.join(", ")}?"
  end
end
