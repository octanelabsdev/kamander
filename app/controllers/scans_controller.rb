# Scans are a stateless read of the filesystem: nothing about a scan is
# persisted beyond the ManagedApp/AppDestination rows the importer upserts.
# Unscannable repos never become rows (schema requires service_name), so
# #show re-runs the scanner to surface them — a sub-second local disk read,
# cheap enough to repeat on every review-page load, and it means the review
# page is always honest about the current state of scan_root instead of
# trusting a stashed copy that a page refresh would lose anyway.
class ScansController < ApplicationController
  def create
    Kamander::Kamal::ScanImporter.new(run_scan).call
    redirect_to scan_path, notice: "Scan complete."
  end

  def show
    scanned_apps = run_scan
    @errored_apps = scanned_apps.select(&:error?)
    @discovered_apps = ManagedApp.discovered.ordered.includes(:app_destinations)
    @hidden_apps = ManagedApp.hidden.ordered.includes(:app_destinations)
  end

  private

    def run_scan
      Kamander::Kamal::ConfigScanner.new(scan_root: Setting.current.expanded_scan_root).call
    end
end
