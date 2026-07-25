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

config :cinema, Cinema.Showtimes,
  source: Cinema.Allocine,
  days: 7,
  cache_ttl_ms: :timer.minutes(30)

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

import_config "#{config_env()}.exs"
