# Cinema

Every cinema showtime in a French city or department, on one page.

Live at [cinema.premiere-ecoute.fr](https://cinema.premiere-ecoute.fr).

The board answers one question — *what can I go and see?* — so it is built like
a departure board rather than a streaming grid: times are the data, and
everything else stays out of their way.

- **Grouped by film or by cinema.** By film answers "where can I see this?", by
  cinema answers "what's on there?".
- **A week at a glance**, with today's started screenings dimmed rather than
  hidden, and a live local clock to read them against.
- **VF and VOST** colour-coded, on the chips and on the filters that select them.
- **Any of 21 cities or 99 departments.** Departments are how small towns are
  reachable: Saint-Brieuc has no page of its own, but Côtes-d'Armor covers it.
- Click a film to see its whole run across the week, in every cinema showing it.

## Running it

```bash
asdf install       # install erlang and elixir
mix setup          # deps, assets
mix phx.server     # starts the server
```

Then [localhost:4000](http://localhost:4000).

```bash
mix test           # run tests
mix quality        # compile --warnings-as-errors, format, credo --strict, dialyzer
mix clean          # format and credo, fixing what it can
mix audit          # retired packages and security advisories
```
