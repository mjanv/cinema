import Config

config :cinema, CinemaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "j+uxDXOrq2TCv7cJ3F6qZ4RJc/Cq2AD0fLbuSs2Z/OyaXF7ypExiN1R0UEJNAy/H",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true

config :cinema, Cinema.Showtimes,
  source: Cinema.StubSource,
  days: 3,
  cache_ttl_ms: 0
