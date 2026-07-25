import Config

config :cinema,
  generators: [timestamp_type: :utc_datetime]

config :cinema, CinemaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CinemaWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Cinema.PubSub,
  live_view: [signing_salt: "ansWTaxn"]

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

config :esbuild,
  version: "0.25.4",
  cinema: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.0",
  cinema: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :cinema, ecto_repos: [Cinema.Repo]

config :cinema, Cinema.Repo,
  database: Path.expand("../priv/cinema_dev.db", __DIR__),
  pool_size: 5,
  # The cache is written from several request processes at once; WAL lets a
  # reader proceed while a writer is mid-transaction.
  journal_mode: :wal,
  busy_timeout: 5_000

config :cinema, Oban,
  engine: Oban.Engines.Lite,
  # SQLite has no LISTEN/NOTIFY; the PG notifier is the default and would fail
  # to load.
  notifier: Oban.Notifiers.PG,
  repo: Cinema.Repo,
  queues: [
    # AlloCiné rate-limits by IP. One at a time, and the worker sleeps between
    # fetches: concurrency alone is not a rate, since each request finishes in
    # ~150ms. See @pace_ms in Cinema.Jobs.FetchDay.
    allocine: [limit: 1]
  ],
  plugins: [
    # Finished jobs are only useful for a short while after the fact.
    {Oban.Plugins.Pruner, max_age: 3600}
  ]

config :cinema, Cinema.Showtimes,
  source: Cinema.Allocine,
  days: 7,
  cache_ttl_ms: :timer.minutes(30)

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

import_config "#{config_env()}.exs"
