Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "status", to: "scenes#status"

      namespace :auth do
        get "session", to: "sessions#show"
        post "register", to: "registrations#create"
        post "login", to: "sessions#create"
        delete "logout", to: "sessions#destroy"
        post "password/forgot", to: "passwords#create"
        patch "password/reset", to: "passwords#update"
        post "oauth/:provider", to: "oauth#start"
        get "oauth/:provider/callback", to: "oauth#callback"
      end

      resources :orders, param: :public_id, only: %i[index show create] do
        member do
          get "files/:kind", to: "orders#download", as: :file
          post "authorize_payment", to: "orders#authorize_payment"
          post "cancel", to: "orders#cancel"
          post "purchase", to: "orders#purchase"
        end
      end
      resources :notifications, only: %i[index] do
        member { patch :read }
      end
      post "payments/stripe/webhook", to: "payments/stripe#webhook"

      namespace :admin do
        get "email_previews/:template", to: "email_previews#show", as: :email_preview
        resources :orders, param: :public_id, only: %i[index show update] do
          member do
            get "files/source/:attachment_id", to: "orders#download_source", as: :source_file
            post "accept"
            post "decline"
            post "approve"
          end
        end
      end

      get "scenes/schema", to: "scenes#schema"
      get "scenes/examples/:name", to: "scenes#example"
      post "scenes/analyze", to: "scenes#analyze"
      post "scenes/compile", to: "scenes#compile"
      post "scenes/export", to: "scenes#export"
    end
  end

  root to: redirect("/index.html")
end
