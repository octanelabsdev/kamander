# No auth by design (127.0.0.1, single-user) — same as the rest of the app.
class OperationsController < ApplicationController
  def show
    @operation = Operation.find(params[:id])
  end

  def create
    destination = AppDestination.where(managed_app: ManagedApp.managed).find(operation_params[:app_destination_id])
    verb = operation_params[:verb].to_s

    return reject(%(Unknown operation "#{verb}".)) unless Operation.verbs.key?(verb)
    return reject(busy_message(destination)) if destination.active_operation

    operation = Operation.new(managed_app: destination.managed_app, app_destination: destination,
      verb: verb, status: :queued, command: "pending")

    begin
      operation.save!
    rescue ActiveRecord::RecordNotUnique
      return reject(busy_message(destination))
    end

    LifecycleJob.perform_later(operation)
    redirect_to operation
  end

  private

    def operation_params
      params.permit(:verb, :app_destination_id)
    end

    def reject(message)
      redirect_back fallback_location: root_path, alert: message
    end

    def busy_message(destination)
      "An operation is already running for #{destination.managed_app.display_label} (#{destination.name || "base"})."
    end
end
