Rails.application.routes.draw do
  root to: 'products#fetch_amazon_data'

  devise_for :users
  get "up" => "rails/health#show", as: :rails_health_check

  resources :products do
    collection do
      get 'fetch_amazon_data'
      get 'save_amazon_data'
    end
  end
end
