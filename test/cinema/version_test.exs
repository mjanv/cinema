defmodule Cinema.VersionTest do
  use ExUnit.Case, async: true

  test "commit/0 is a short SHA baked in at compile time" do
    # A release has no .git directory, so this must be resolved when the code is
    # compiled, not when it runs.
    commit = Cinema.Version.commit()

    assert is_binary(commit)
    assert String.match?(commit, ~r/^[0-9a-f]{7,12}$|^unknown$/)
  end

  test "commit/0 is stable across calls" do
    assert Cinema.Version.commit() == Cinema.Version.commit()
  end
end
