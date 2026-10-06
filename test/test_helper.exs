Ecto.Adapters.SQL.Sandbox.mode(Sortir.Core.Repo, :manual)

# capture_log: a passing test prints nothing, a failing one prints everything it
# logged. Error-path tests log deliberately, and without this the suite output
# is noise that buries the one line worth reading.
ExUnit.start(capture_log: true)
