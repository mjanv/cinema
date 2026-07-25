import Config

config :cinema, CinemaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "F80YpSwEWCf+MWF4qPWC0zXmKkfRpSaBNC9FVA11iR7AcUxb2dQ0OYzli4MI4zXz",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:cinema, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:cinema, ~w(--watch)]}
  ]

config :cinema, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

# Query logging is noise for a cache table hit on every request.
config :cinema, Cinema.Repo, log: false
