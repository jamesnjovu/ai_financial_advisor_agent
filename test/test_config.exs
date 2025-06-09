# Additional test configuration
import Config

# Configure test database with vector extension
config :app, App.Repo,
       pool: Ecto.Adapters.SQL.Sandbox,
       pool_size: System.schedulers_online() * 2

# Disable external API calls in tests
config :app, :openai,
       api_key: "test_key",
       model: "gpt-4-test"

config :app, :google_oauth,
       client_id: "test_google_client_id",
       client_secret: "test_google_client_secret",
       redirect_uri: "http://localhost:4002/auth/google/callback"

config :app, :hubspot_oauth,
       client_id: "test_hubspot_client_id",
       client_secret: "test_hubspot_client_secret",
       redirect_uri: "http://localhost:4002/auth/hubspot/callback"

# Fast password hashing for tests
config :bcrypt_elixir, :log_rounds, 1

# Disable SSL for test HTTP clients
config :app, :http_client_options, [
  ssl: [verify: :verify_none],
  recv_timeout: 1000
]
