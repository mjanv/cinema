# Cinema — deployment checklist

Everything in the repo is ready. This is the list of things that still have to
happen on the outside: DNS, the droplet, and GitHub. Nothing here has been done
yet.

Target: `https://cinema.premiere-ecoute.fr`, second app on the droplet that
already runs Première Écoute (`68.183.219.251`).

---

## 0. Prerequisite — already done

- [x] Première Écoute deployed with Traefik's `directory:` provider

Everything below assumes `/opt/traefik/traefik.yml` contains
`directory: /opt/traefik/dynamic`. Confirm before starting:

**http://68.183.219.251:8080** → HTTP → Routers → `app-domain` and `twitch-ws`
should be listed. (`cinema` appears only after step 4.)

---

## 1. DNS

Add an A record with your registrar:

```
cinema.premiere-ecoute.fr.   A   68.183.219.251
```

Do this **first**. Let's Encrypt validates over HTTP, so the certificate cannot
be issued until the name resolves. Wait for propagation before step 4:

```bash
dig +short cinema.premiere-ecoute.fr    # must print 68.183.219.251
```

---

## 2. Check there is room on the droplet

1 GB total, already running PostgreSQL, SeaweedFS, Traefik and Première Écoute
(capped at 600 MB). Cinema asks for 150 MB.

```bash
ssh root@68.183.219.251 'free -m'
```

If available memory is under ~200 MB, lower `MemoryMax` in
`apps/digital_ocean/systemd/cinema.service` before deploying, or skip cinema's
boot cache warm (`config/prod.exs`, `warm_on_boot`).

---

## 3. Provision the server

```bash
rsync -avz apps/digital_ocean/ root@68.183.219.251:/tmp/cinema-setup/
ssh root@68.183.219.251 'bash /tmp/cinema-setup/setup.sh'
```

Creates the `cinema` system user and `/opt/cinema`, installs and enables the
systemd unit, and drops `cinema.yml` into `/opt/traefik/dynamic/`.

Idempotent — safe to re-run. It **exits with an error** if Traefik is still on
the old single-file provider, rather than half-configuring.

The service will not start yet: there is no release in `/opt/cinema` until the
first deploy. That is expected.

---

## 4. GitHub

### 4.1 Repository

```bash
git add -A
git commit -m "Cinema showtimes board"
gh repo create cinema --private --source=. --remote=origin
```

`.gitignore` already excludes `.env*`, `_build`, `deps` and PLT files — verified
nothing sensitive is staged.

### 4.2 Secrets and variables

**Settings → Secrets and variables → Actions**

| Name | Kind | Value |
|------|------|-------|
| `CINEMA_SECRET_KEY_BASE` | secret | output of `mix phx.gen.secret` |
| `DO_SSH_PRIVATE_KEY` | secret | the same deploy key Première Écoute uses |
| `DO_HOST` | **variable** | `68.183.219.251` |

`DO_HOST` is a *variable*, not a secret — the workflow reads it as `vars.DO_HOST`.

`PHX_HOST` and `PORT` are hardcoded in the workflow on purpose: not sensitive,
and keeping the topology visible in the repo makes it reviewable.

### 4.3 Deploy

```bash
git push -u origin main
```

The workflow builds on OTP 29.0.2 / Elixir 1.20.2, runs the tests, backs up
`/opt/cinema`, rsyncs the release, restarts the service, then polls `/health`
for 60 s — rolling back automatically if it never answers.

---

## 5. Verify

```bash
curl -fsS https://cinema.premiere-ecoute.fr/health && echo
```

- **http://68.183.219.251:8080** → HTTP → Routers → a `cinema` router
- `ssh root@68.183.219.251 'journalctl -u cinema -n 50 --no-pager'`
  → look for `Showtimes cache warmed: 7 days, N theaters`
- Open the site on your phone. Tap a day, switch **Par film** / **Par cinéma**,
  filter VF/VOST. **If the buttons do nothing, see below.**

And confirm the neighbour is unharmed:

```bash
curl -fsS -o /dev/null https://premiere-ecoute.fr/health && echo "premiere-ecoute OK"
```

---

## If something breaks

**Buttons do nothing / page renders but is dead.** The LiveView websocket is
failing. Almost always `check_origin`: Phoenix rejects sockets whose Origin does
not match `PHX_HOST`. Check the browser console for a failed `/live/websocket`,
and confirm `PHX_HOST=cinema.premiere-ecoute.fr` in `/opt/cinema/.env`. The page
looks fine on first load, so this reads like a frontend bug and is not one.

**404 from Traefik.** `cinema.yml` never loaded. Check
`/opt/traefik/dynamic/cinema.yml` exists and the dashboard lists the router.

**TLS error.** Let's Encrypt could not validate — usually DNS had not propagated
when Traefik first tried. It retries; check `journalctl -u traefik | grep -i acme`.

**Service restart-looping.** `journalctl -u cinema -n 100`. If it is OOM, raise
`MemoryMax` in the unit file.

**Rollback by hand:**

```bash
ssh root@68.183.219.251 'systemctl stop cinema && rm -rf /opt/cinema && mv /opt/cinema-backup /opt/cinema && systemctl start cinema'
```

---

## Notes

**OTP must match.** Releases embed ERTS and are not portable across OTP majors.
The droplet, CI and `.tool-versions` are all on 29.0.2 / 1.20.2. If you upgrade
the droplet, update `.tool-versions` and the workflow together.

**Nothing to back up.** No database. The schedule is fetched from AlloCiné's
JSON API into ETS with a 30-minute TTL; losing it costs one refetch.

**Isolation.** Distinct systemd unit, user, port (4001), release node name and
`/opt` directory. Each app owns one file in `/opt/traefik/dynamic/`, so neither
deploy can take the other down. Cinema binds to `127.0.0.1` only — Traefik is
the sole thing that reaches it.

**Keep it unindexed.** `robots.txt` disallows everything and the layout sends
`noindex, nofollow`. This republishes AlloCiné's data; a personal tool is fine,
a search-indexed public mirror is not.
