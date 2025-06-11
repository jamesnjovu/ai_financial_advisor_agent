import Config

# Configure your database
if database_url = System.get_env("DATABASE_URL") do
  config :app, App.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: [],
    types: App.PostgrexTypes
else
  config :app, App.Repo,
    username: "postgres",
    password: "Qwerty12",
    hostname: "localhost",
    database: "ai_financial_advisor_db",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10,
    types: App.PostgrexTypes
end

config :app, AppWeb.Endpoint,
  http: [
    ip: {127, 0, 0, 1},
    port: 4500
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "buk4+gNRIJ8KvtCoYtiW9VSfnZAExQjC0RPblsrTPJCBk+NvM47YqU34PFQJ/6iA",
  watchers: [
    esbuild: {
      Esbuild,
      :install_and_run,
      [:app, ~w(--sourcemap=inline --watch)]
    },
    tailwind: {
      Tailwind,
      :install_and_run,
      [:app, ~w(--watch)]
    }
  ]

config :app, AppWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/app_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :app, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include HEEx debug annotations as HTML comments in rendered markup
  debug_heex_annotations: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
