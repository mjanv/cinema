defmodule CinemaWeb.HealthController do
  @moduledoc """
  Liveness probe for the deploy pipeline.

  Deliberately answers without touching AlloCiné or the cache: a slow upstream
  must not make a healthy release look dead and trigger a rollback.
  """

  use CinemaWeb, :controller

  def index(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
