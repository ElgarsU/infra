# VPS inventory

Live inventory of the single VPS that runs everything. Keep this current — any
new app or port change updates this file as part of the deploy contract.

## The box

| | |
|---|---|
| Provider / type | Hetzner **CAX11** (ARM64, 2 vCPU, 4 GB RAM, ~40 GB) |
| OS | Ubuntu 24.04 LTS (aarch64) |
| Location | Helsinki (hel1) |
| Public IP | `89.167.98.246` |
| Access | `ssh root@89.167.98.246` (key-only; password auth disabled) |
| Control node | local laptop (ARM64 Mac), Ansible from this infra repo |
| Deploy | `./deploy.sh <app>` per app; `./setup.sh` for a full rebuild |

**Out-of-band prerequisites (not managed by Ansible):**
- **Hetzner cloud firewall** (separate from ufw): must allow inbound `22/tcp`,
  `80/tcp`, `443/tcp`, `5027/tcp`. **ICMP is deliberately blocked here** (the
  box does not answer pings — do not "fix" this).
- **Cloudflare DNS** for `elgars.eu` (see DNS conventions below).
- **Caddy** must be installed (Ubuntu `caddy` package) before `setup.sh`.

## Apps

| App | Subdomain | Public port | Localhost port | systemd unit | DB | System user | Depends on |
|---|---|---|---|---|---|---|---|
| **tracker** (Traccar) | `track.elgars.eu` | **5027/tcp** (device) | 8082 (web) | `traccar.service` | Postgres `traccar` | `traccar` | postgres, caddy |
| **sentry** | (via `track.elgars.eu/sentry-health`) | — | 8091 (health) | `sentry.service` | SQLite `/var/lib/sentry/state.db` | `sentry` (+`enduro-data`) | tracker, common |
| **husky** | `husky.elgars.eu` | — | 3001 | `husky.service` | SQLite `/opt/husky/data/husky.sqlite` (+reads sentry's) | `husky` (+`enduro-data`) | tracker, sentry, caddy, Node |
| **discord-scraper** | — (no web) | — | — | `discord-scraper.service` + `.timer` | SQLite `/opt/discord-scraper/data/scraper.db` | `discord-scraper` | — |
| **tet-fit** | `fit.elgars.eu` | — | 3000 | `tet-training.service` | JSON files `/opt/tet-training/data` | `www-data` | caddy, Node |
| **prelander** | `elgars.eu` + `www.elgars.eu` | — | — (Caddy file_server) | none | none | `caddy` (files `root:caddy`) | caddy |

Notes:
- `discord-scraper` is a **scheduled** job (systemd timer: 08:00 / 12:40 /
  17:20 / 22:00 Europe/Riga), `Type=oneshot`, no long-running process, no ports.
- `tet-fit`'s unit/dir/service are named **`tet-training`** (historical); the
  repo + infra app are **`tet-fit`** (`git@github.com:ElgarsU/tet-fit.git`).
- All localhost ports (8082, 8091, 3000, 3001) and Postgres `5432` bind to
  `127.0.0.1` only and are reverse-proxied (or not exposed). Never opened in ufw.

## Shared infrastructure

### Caddy (reverse proxy) — base `caddy` role
- TLS via **Cloudflare DNS-01** (`caddy-dns/cloudflare` plugin) — required
  because origin 80/443 is locked to Cloudflare IPs, so HTTP-01 can't work.
- `/etc/caddy/Caddyfile` is **imports-only**: `import snippets/*.caddy` +
  `import sites.d/*.caddy`.
- `/etc/caddy/snippets/security.caddy` — shared `(security_headers)` snippet
  (HSTS, nosniff, frame-deny, referrer policy, `-Server`).
- `/etc/caddy/sites.d/<host>.caddy` — **one file per app**, written by that
  app's role: `track.`, `husky.`, `fit.`, `elgars.eu`.
- `/etc/caddy/cloudflare.env` — holds `CF_API_TOKEN`, loaded by `caddy.service`
  via a systemd drop-in. Single source: `secrets/common.env`.
- Gotcha: `caddy validate` needs `CF_API_TOKEN` in the env, so every validate
  step does `set -a; source /etc/caddy/cloudflare.env; caddy validate …`.

### PostgreSQL — base `postgres` role
- Single instance, **localhost-bound** (asserted, never mutated). Ubuntu main
  unversioned package (PG 16 on 24.04).
- Databases: only **`traccar`** today (role `traccar`, created by the tracker
  app). The "shared DB, multiple databases" model — new apps add their own DB.

### ufw posture — base `common` role
- Default **deny incoming / allow outgoing**. `22/tcp` allowed before enable
  (anti-lockout).
- `80/443` restricted to **Cloudflare IP ranges** by `/etc/cron.monthly/cf-ufw-update.sh`
  (refreshed monthly; adds new rules before deleting old).
- `5027/tcp` opened by the tracker app (`ufw limit`, rate-limited; or per-CIDR
  if `traccar_device_source_ranges` is set).
- **ICMP** block lives at the Hetzner cloud firewall (out-of-band), not ufw.

### Host hardening — base `common` role
- `fail2ban` sshd jail (5 retries / 10m → 1h ban).
- sshd drop-in: `PermitRootLogin prohibit-password`, no password/keyboard auth,
  `MaxAuthTries 3`, `AllowUsers root`.
- `unattended-upgrades` with auto-reboot at 03:00.
- Node.js 20 via NodeSource (for husky + tet-fit).

### Cloudflare DNS conventions
- `track.elgars.eu` — **orange-cloud** (proxied) → `89.167.98.246`. Web UI.
- `gps.elgars.eu` — **gray-cloud** (DNS-only A record) → `89.167.98.246`. Raw
  TCP `5027` device ingest (FMC880); can't be proxied.
- `husky.elgars.eu`, `fit.elgars.eu` — orange-cloud → `89.167.98.246`.
- `elgars.eu` + `www.elgars.eu` — orange-cloud (apex) → `89.167.98.246`.
- MX / mail records (Gandi) must stay untouched.

### Monitoring
- **UptimeRobot** (external): probes `https://track.elgars.eu/sentry-health`
  (sentry liveness) and the app subdomains.

## Cross-app coordination

- **`enduro-data` group** — created by the `common` role. Members: `sentry`
  (primary use) and `husky`, each added by **its own** app role with
  `append: true`, then asserted. Grants shared rw on `/var/lib/sentry/state.db`
  (setgid `2770`, `UMask=002`, + `EnsureSharedPerms` in sentry — see CLAUDE.md).
- **Pushover credentials** — single source `secrets/tracker.env`
  (`PUSHOVER_USER` / `PUSHOVER_TOKEN`). Used by **tracker** (Traccar notificator)
  and **sentry** (emergency alerts). `sentry/deploy.sh` also sources `tracker.env`.
- **Traccar read-only users** — tracker creates a `husky` user (consumed by the
  husky app, creds in `tracker.env`) and `sentry` creates its own `sentry` user.
  Both `administrator=false readonly=true`, linked only to the FMC880 device.
- **FMC880 device** (IMEI `862129081248340`) must exist in Traccar before sentry
  deploys — tracker pre-registers it.

## Conventions for a new app

- **Ports:** localhost app servers use the 3000-block (3000 tet-fit, 3001
  husky). Pick the next free (3002, 3003, …). Bind `127.0.0.1` only; never open
  in ufw unless it's a raw public listener like Traccar's 5027.
- **Subdomain:** `<app>.elgars.eu`, orange-cloud in Cloudflare → `89.167.98.246`.
- **System user:** a dedicated system user named after the app
  (`shell=/usr/sbin/nologin`, `create_home:false`, app dir under `/opt/<app>`).
  Don't reuse names across apps.
- **systemd hardening defaults:** `ProtectSystem=strict`, `ProtectHome=yes`,
  `PrivateTmp=yes`, `NoNewPrivileges=yes`, explicit `ReadWritePaths`.
- **Secrets:** `secrets/<app>.env` (gitignored) + `secrets/<app>.env.example`.
  Read in the playbook via `lookup('env', 'KEY')`.

See `adding-a-new-app.md` for the full procedure.
