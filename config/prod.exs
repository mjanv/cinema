import Config

config :sortir, SortirWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

config :sortir, SortirWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      # paths: ["/health"],
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

config :logger, level: :info

config :sortir, Sortir.Cinema.Showtimes,
  warm_on_boot: true,
  cache_ttl_ms: :timer.hours(12)

# Only scrapes when the agenda has gone stale, so a redeploy does not re-read
# every venue.
config :sortir, Sortir.Agenda.Warmer, scrape_on_boot: true
