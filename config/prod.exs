import Config

config :cinema, CinemaWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

config :cinema, CinemaWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      # paths: ["/health"],
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

config :logger, level: :info

config :cinema, Cinema.Showtimes,
  warm_on_boot: true,
  cache_ttl_ms: :timer.hours(3)
