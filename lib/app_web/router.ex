defmodule AppWeb.Router do
  use AppWeb, :router
  alias AppWeb.Plugs.Auth
  import Auth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AppWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", AppWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/", PageController, :home

    scope "/auth" do
      # Google auth
      get "/login", AuthController, :login
      get "/google/callback", AuthController, :google_callback
    end
  end

  scope "/", AppWeb do
    pipe_through [:browser, :require_authenticated_user]

    # Hubspot auth
    get "/auth/hubspot", AuthController, :connect_hubspot
    get "/auth/hubspot/callback", AuthController, :hubspot_callback

    live_session :authenticated, on_mount: {Auth, :ensure_authenticated} do
      live "/chat", ChatLive
      live "/chat/:conversation_id", ChatLive
      live "/settings", SettingsLive
    end
  end

  # Webhook endpoints
  scope "/webhooks", AppWeb do
    pipe_through :api

    post "/gmail", WebhookController, :gmail_webhook
    post "/hubspot", WebhookController, :hubspot_webhook
    post "/calendar", WebhookController, :calendar_webhook
    get "/health", WebhookController, :health
  end

  if Application.compile_env(:app, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/", AppWeb do
    pipe_through :browser

    delete "/auth/logout", AuthController, :logout
    get "/.well-known/appspecific/com.chrome.devtools.json", PageController, :devtools
  end
end
