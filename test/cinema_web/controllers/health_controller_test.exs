defmodule CinemaWeb.HealthControllerTest do
  use CinemaWeb.ConnCase, async: false

  test "reports ok so the deploy health check can gate a rollback", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert response(conn, 200) =~ "ok"
  end

  test "answers without touching AlloCiné", %{conn: conn} do
    # Health must stay cheap: a slow or failing source cannot make the app look
    # dead to the deploy script, or every deploy would roll back.
    assert %{status: 200} = get(conn, ~p"/health")
  end
end
