defmodule Cinema.ScreeningTest do
  use ExUnit.Case, async: true

  alias Cinema.Screening

  defp at(time) do
    %Screening{
      theater_id: "T1",
      title: "Film",
      starts_at: NaiveDateTime.from_iso8601!(time),
      date: ~D[2026-07-26],
      version: :vf
    }
  end

  test "a screening that has already started is past" do
    assert Screening.past?(at("2026-07-26T14:00:00"), ~N[2026-07-26 20:00:00])
  end

  test "a screening still to come is not past" do
    refute Screening.past?(at("2026-07-26T22:00:00"), ~N[2026-07-26 20:00:00])
  end

  test "a screening starting right now is not yet past" do
    refute Screening.past?(at("2026-07-26T20:00:00"), ~N[2026-07-26 20:00:00])
  end

  test "yesterday's late screening is past even though its clock time is later" do
    assert Screening.past?(at("2026-07-25T23:00:00"), ~N[2026-07-26 09:00:00])
  end
end
