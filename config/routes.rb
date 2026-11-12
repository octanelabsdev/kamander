Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "managed_apps#index"

  resource :scan, only: %i[create show]
  resource :setting, only: %i[edit update]
  resource :status_refresh, only: :create

  resources :managed_apps, only: %i[index show update destroy] do
    post :confirm, on: :collection
    get :resource_usage, on: :member, to: "resource_usages#show"
    resources :ci_launches, only: :create
  end

  resources :operations, only: %i[show create]

  get "ci", to: "ci_runs#index", as: :ci_runs
  get "ci/latest", to: "ci_runs#latest", as: :latest_ci_runs
  get "ci/runs/:id", to: "ci_runs#show", as: :ci_run
  post "ci/runs/:id/cancel", to: "ci_runs#cancel", as: :cancel_ci_run
  resources :ci_launches, only: :show, path: "ci/launches"
end
