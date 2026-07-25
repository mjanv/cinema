defmodule Cinema.MixProject do
  use Mix.Project

  def project do
    [
      app: :cinema,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: dialyzer(),
      default_task: "phx.server"
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "_build/#{Mix.env()}/dialyzer",
      plt_core_path: "_build/#{Mix.env()}/dialyzer",
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :extra_return, :missing_return, :underspecs]
    ]
  end

  def application do
    [
      mod: {Cinema.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [quality: :dev]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Web
      {:bandit, "~> 1.5"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      # Backend
      {:dns_cluster, "~> 0.2.0"},
      {:jason, "~> 1.2"},
      {:req, "~> 0.5"},
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.17"},
      {:oban, "~> 2.23"},
      {:exqlite, "~> 0.27"},
      {:tz, "~> 0.28"},
      # Observability
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind cinema", "esbuild cinema"],
      # compile first: the Elixir compiler emits
      # _build/$MIX_ENV/phoenix-colocated/cinema/colocated.css, which app.css
      # imports. Without it tailwind fails to resolve that import on a clean
      # checkout (CI), even though a local _build makes it look fine.
      "assets.deploy": [
        "compile",
        "tailwind cinema --minify",
        "esbuild cinema --minify",
        "phx.digest"
      ],
      quality: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ],
      clean: ["format", "credo --strict"],
      # ecto.create/migrate before test: the app boots Oban, which verifies its
      # tables exist, and in test the sandbox pool cannot serve a checkout
      # early enough for a boot-time migration.
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      audit: ["hex.audit", "deps.unlock --check-unused"]
    ]
  end
end
