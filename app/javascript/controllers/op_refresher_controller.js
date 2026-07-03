import { Controller } from "@hotwired/stimulus"

// Self-heals an operation console that finished before its Turbo Stream
// subscription was established — fast ops can complete in ~1-2s, quicker
// than that round-trip, so the broadcasts land with nobody listening.
// Polls a fresh copy of the page while the operation is still active; the
// server stops rendering this controller at all once it's terminal, so the
// element disappears on the next visit and polling simply stops.
export default class extends Controller {
  static values = { interval: { type: Number, default: 2000 } }

  connect() {
    this.timer = setInterval(() => Turbo.visit(window.location.href, { action: "replace" }), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
