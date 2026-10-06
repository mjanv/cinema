defmodule CinemaWeb.Router do
  use CinemaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CinemaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Locked only when there is a password to lock it with.
  pipeline :operator do
    plug :authenticate_operator
  end

  scope "/", CinemaWeb do
    pipe_through :browser

    live "/", ShowtimesLive, :index
  end

  scope "/", CinemaWeb do
    pipe_through [:browser, :operator]

    live "/traffic", TrafficLive, :index
  end

  # No session or CSRF: the deploy health check is a bare liveness probe.
  scope "/", CinemaWeb do
    get "/health", HealthController, :index
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:cinema, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CinemaWeb.Telemetry
    end
  end

  # The password is optional: set one and the dashboard asks for it, leave it
  # out and the dashboard is simply open. An empty password counts as no
  # password -- an unset deploy secret reaches the release as "", and a
  # dashboard that opens to a blank password would be worse than an open one,
  # because it would look locked.
  #
  # Open by default means an unset OPERATOR_PASSWORD publishes the numbers to
  # anyone who finds the path. They are counts of board views with no visitor
  # in them, which is why that is a reasonable default rather than a hole --
  # but a public deploy that would rather not show them needs the password set.
  defp authenticate_operator(conn, _opts) do
    case Application.get_env(:cinema, :operator) do
      [username: username, password: password]
      when is_binary(password) and byte_size(password) > 0 ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password)

      _no_password ->
        conn
    end
  end
end
