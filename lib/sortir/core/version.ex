defmodule Cinema.Version do
  @moduledoc """
  Which build is running.

  Resolved at **compile time**: an OTP release ships without a `.git`
  directory, so asking git at runtime would return nothing on the server. CI
  provides `GITHUB_SHA`; a local build falls back to asking git directly.
  """

  @commit (case System.get_env("GITHUB_SHA") do
             sha when is_binary(sha) and byte_size(sha) >= 7 ->
               String.slice(sha, 0, 7)

             _absent ->
               case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
                 {sha, 0} -> String.trim(sha)
                 _no_git -> "unknown"
               end
           end)

  @doc "Short commit SHA of the running build, or `unknown` if it could not be determined."
  @spec commit() :: String.t()
  def commit, do: @commit
end
