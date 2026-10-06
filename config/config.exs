import Config

config :sortir,
  generators: [timestamp_type: :utc_datetime]

config :sortir, SortirWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SortirWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Sortir.Core.PubSub,
  live_view: [signing_salt: "ansWTaxn"]

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

config :esbuild,
  version: "0.25.4",
  sortir: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.0",
  sortir: [
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

config :sortir, ecto_repos: [Sortir.Core.Repo]

config :sortir, Sortir.Core.Repo,
  database: Path.expand("../priv/sortir_dev.db", __DIR__),
  pool_size: 5,
  # The cache is written from several request processes at once; WAL lets a
  # reader proceed while a writer is mid-transaction.
  journal_mode: :wal,
  busy_timeout: 5_000

config :sortir, Oban,
  engine: Oban.Engines.Lite,
  # SQLite has no LISTEN/NOTIFY; the PG notifier is the default and would fail
  # to load.
  notifier: Oban.Notifiers.PG,
  repo: Sortir.Core.Repo,
  queues: [
    # AlloCiné rate-limits by IP. One at a time, and the worker sleeps between
    # fetches: concurrency alone is not a rate, since each request finishes in
    # ~150ms. See @pace_ms in Sortir.Cinema.Jobs.FetchDay.
    allocine: [limit: 1],
    # Its own queue: a slow or broken venue scraper must not stall showtimes.
    # One at a time is plenty — a venue is one page a month, not 525 requests.
    agenda: [limit: 1],
    # The channel's RSS feed: one request, but the same one-at-a-time rule.
    videos: [limit: 1]
  ],
  plugins: [
    # Finished jobs are only useful for a short while after the fact.
    {Oban.Plugins.Pruner, max_age: 3600},
    # Venues add shows continuously, and the boot warmer only runs on restart:
    # without this a long-lived server serves an increasingly stale agenda.
    # 04:00 local, when the venues' sites are idle. A job with no `source`
    # fans out to every source — see `Sortir.Agenda.Jobs.ScrapeVenue`.
    {Oban.Plugins.Cron,
     timezone: "Europe/Paris",
     crontab: [
       {"0 4 * * *", Sortir.Agenda.Jobs.ScrapeVenue},
       # The feed lists only the 15 newest videos, about three days' worth, so
       # every three hours leaves a wide margin. Opening the page also fetches
       # (rate limited), which is what keeps it fresh for a visitor.
       {"0 */3 * * *", Sortir.Videos.Jobs.Fetch},
       # Videos older than a month are not worth browsing; once a day is plenty.
       {"30 4 * * *", Sortir.Videos.Jobs.Prune}
     ]}
  ]

config :sortir, Sortir.Core.Clock, timezone: "Europe/Paris"

config :sortir, Sortir.Cinema.Showtimes,
  source: Sortir.Cinema.Allocine,
  days: 7,
  cache_ttl_ms: :timer.minutes(30)

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

import_config "#{config_env()}.exs"
