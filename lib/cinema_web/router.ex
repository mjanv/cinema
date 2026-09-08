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

  # The traffic it reports is nobody's business but the operator's, and the
  # page is one password away from being a public list of which cities the app
  # is worth running for.
  pipeline :operator do
    plug :require_operator
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

  # Fails closed: without a password the page does not exist, so a deploy that
  # forgets to set one exposes nothing rather than everything. An empty
  # password counts as unset -- an unset secret reaches the release as "",
  # and letting that through would be worse than no password at all.
  defp require_operator(conn, _opts) do
    case Application.get_env(:cinema, :operator) do
      [username: username, password: password]
      when is_binary(password) and byte_size(password) > 0 ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password)

      _unconfigured ->
        conn |> send_resp(:not_found, "") |> halt()
    end
  end
end
