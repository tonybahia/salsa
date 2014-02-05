Salsa::Application.routes.draw do
  root 'default#index'

  resources :syllabuses
  get "canvas/list_courses"
  get "oauth2/login"
  get "oauth2/callback"
end
