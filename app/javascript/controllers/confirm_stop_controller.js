import { Controller } from "@hotwired/stimulus"

// Typed-confirm for stopping a production destination — the real submit
// button stays disabled until the operator types the app's name exactly.
export default class extends Controller {
  static targets = ["dialog", "input", "submit"]
  static values = { serviceName: String }

  open() {
    this.dialogTarget.classList.remove("hidden")
    this.inputTarget.focus()
  }

  close() {
    this.dialogTarget.classList.add("hidden")
    this.inputTarget.value = ""
    this.submitTarget.disabled = true
  }

  check() {
    this.submitTarget.disabled = this.inputTarget.value !== this.serviceNameValue
  }
}
