# Deployment Guide - Digital Ocean

Cinema runs as a second, independent app on the droplet that already hosts
Première Écoute. It shares only Traefik; there is no shared database, no shared
release, and neither app's deploy can break the other.

## Prerequisites

- The droplet is already provisioned by Première Écoute's `setup.sh`
  (Traefik, Let's Encrypt, UFW, SSH). This guide does **not** repeat that.
- Traefik must use the directory provider (`directory: /opt/traefik/dynamic`).
  Already applied on the droplet; the matching config is committed in the
  premiere-ecoute repo so its own deploys stay consistent.
- DNS: `cinema.premiere-ecoute.fr` A record → the droplet IP.

## Architecture

```
Internet
    ↓
Traefik (ports 80, 443)          shared
    ├── premiere-ecoute.fr        → port 4000, user `premiere`, /opt/premiere-ecoute
    └── cinema.premiere-ecoute.fr → port 4001, user `cinema`,   /opt/cinema
```

Everything is namespaced away from the other app: systemd unit `cinema`,
release node `cinema` (an sname collision would stop the second app booting),
port 4001, and its own service account.

There is **no database**. The schedule is fetched from AlloCiné and held in
ETS with a 30-minute TTL, so there are no migrations and nothing to back up —
losing the cache costs one refetch.

## First-time setup

```bash
rsync -avz apps/digital_ocean/ root@<DROPLET_IP>:/tmp/cinema-setup/
ssh root@<DROPLET_IP> 'bash /tmp/cinema-setup/setup.sh'
```

`setup.sh` is idempotent. It creates the `cinema` system account and
`/opt/cinema`, installs the systemd unit, verifies Traefik is using the
directory provider (and refuses to continue if not), and installs
`/opt/traefik/dynamic/cinema.yml`.

## GitHub Actions

Push to `main` triggers `.github/workflows/release-app.yml`:

1. Build the release on OTP 29.0.2 / Elixir 1.20.2 — **must** match the droplet;
   releases embed ERTS and are not portable across OTP majors
2. Run the test suite
3. Back up `/opt/cinema`, rsync the new release, install `cinema.yml`
4. `systemctl restart cinema`
5. Poll `https://cinema.premiere-ecoute.fr/health` for 60s
6. Roll back to the backup if the health check fails

### Required secrets and variables

| Name | Kind | Value |
|------|------|-------|
| `CINEMA_SECRET_KEY_BASE` | secret | `mix phx.gen.secret` |
| `DO_SSH_PRIVATE_KEY` | secret | same deploy key Première Écoute uses |
| `DO_HOST` | variable | droplet IP or hostname |

`PHX_HOST` and `PORT` are set inline in the workflow, not as secrets — they are
not sensitive and keeping them in the repo makes the topology reviewable.

## Verify

```bash
ssh root@<DROPLET_IP> 'systemctl status cinema --no-pager'
ssh root@<DROPLET_IP> 'journalctl -u cinema -n 50 --no-pager'
curl -fsS https://cinema.premiere-ecoute.fr/health && echo
```

The Traefik dashboard at `http://<DROPLET_IP>:8080` under **HTTP → Routers**
should list a `cinema` router. If it does not, Traefik never loaded
`dynamic/cinema.yml` — check the file exists and that the provider is
`directory:`, not `filename:`.

A healthy boot logs the cache warm:

```
[info] Showtimes cache warmed: 7 days, 24 theaters, 242ms
```

The page footer shows the short commit SHA of the running build, so you can
confirm a deploy landed without opening the Actions log.

## Management

```bash
ssh root@<DROPLET_IP> 'systemctl restart cinema'
ssh root@<DROPLET_IP> 'journalctl -u cinema -f'
ssh root@<DROPLET_IP> '/opt/cinema/bin/cinema remote'   # IEx on the running node
```

## Resource budget

The unit caps the app at `MemoryMax=300M` / `CPUQuota=40%`. The droplet has
~2 GB with ~1 GB free while running PostgreSQL, SeaweedFS, Traefik and
Première Écoute. Measured idle usage is ~115 MB after warming 7 days of
showtimes. Check headroom after a deploy:

```bash
ssh root@<DROPLET_IP> 'free -m; systemctl show cinema -p MemoryCurrent'
```

If `MemoryCurrent` sits near the cap, raise `MemoryMax` in
`apps/digital_ocean/systemd/cinema.service` rather than letting the OOM killer
restart the service.

## Caveats

**The data sources are undocumented.** Two different mechanisms, both
unofficial and both able to change without notice:

| Data | Mechanism | Parsed by |
|------|-----------|-----------|
| Showtimes | JSON API, `/_/showtimes/theater-{id}/d-{date}/` | `Cinema.Allocine.Parser` |
| Cities & theaters | HTML scraping of `/salle/` | `Cinema.Allocine.Cities` |

Both are covered by tests against saved fixtures in `test/support/fixtures/`;
if the board empties, look there first. The JSON API is the more stable of the
two — it returns structured fields — whereas the city list depends on page
markup, which is why `Cities` also ships a built-in fallback list.

A failed fetch keeps the last good schedule and marks it stale in the footer
rather than blanking the page.

**Do not make this public.** `robots.txt` disallows everything and the layout
sends `noindex, nofollow`, which keeps a personal tool from becoming a search-
indexed mirror of someone else's data.
