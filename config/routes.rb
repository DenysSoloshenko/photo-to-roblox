Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "status", to: "scenes#status"
      get "scenes/schema", to: "scenes#schema"
      post "scenes/analyze", to: "scenes#analyze"
      post "scenes/compile", to: "scenes#compile"
      post "scenes/export", to: "scenes#export"
    end
  end

  root to: redirect("/index.html")
end
