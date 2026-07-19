# CLAUDE.md — infra

Context for future Claude sessions working in this repo. Read this before
touching deploys.

## What this is

The **single source of truth** for deploying every app to one Hetzner VPS. It
was created by consolidating the deploy logic that used to live in 5 app repos.
After migration, each app repo contains only application code + a `build.sh`;
everything about *how it's deployed* lives here.

- VPS: Hetzner **CAX11** (ARM64), Ubuntu 24.04, `89.167.98.246`, Helsinki.
- Apps deployed here: **tracker** (Traccar GPS server), **sentry** (Go anti-theft
  alerter), **husky** (Nuxt SSR dashboard), **discord-scraper** (Python scraper,
  timer), **forge** (Nuxt SPA), **prelander** (static site), **honda** (Nuxt
  SSR CRF300L maintenance log — standalone, no cross-app deps).
- Full live layout: `docs/vps-inventory.md`.

## Architecture

```
./deploy.sh <app>  →  apps/<app>/deploy.sh  →  (load secrets, clone main,
                       build.sh, ansible-playbook apps/<app>/ansible/playbook.yml)
./setup.sh         →  ansible/site.yml (common, caddy, postgres) then every app
```

- **Base roles** (`ansible/site.yml`): `common` (packages incl. Node 20,
  enduro-data group, fail2ban, sshd hardening, unattended-upgrades, ufw), `caddy`
  (cloudflare-dns plugin, cloudflare.env, sites.d/snippets, imports-only
  Caddyfile), `postgres` (shared instance, localhost-bound). These were extracted
  from the old husky `setup.yml` (the most mature base config) + tracker's PG.
- **App plays** (`apps/<app>/ansible/playbook.yml`): self-contained plays that
  assume the base roles have run. Each writes its own `/etc/caddy/sites.d/*.caddy`
  and owns its own system user.
- **`apps/_lib/deploy-common.sh`**: shared `log/die`, `load_env_files`,
  `clone_repo`, `build_clone`, `ansible_app`. App `deploy.sh` files are ~5 lines.

## Conventions (do not break these)

- **`git pull` this infra repo before every deploy.** `./deploy.sh` runs entirely
  from the *local* checkout (scripts, Ansible templates, secrets) — only the app
  source is pulled fresh (`clone_repo` clones the app's `main`). A stale infra
  checkout silently deploys old config. Always `git pull --ff-only` here first.
- **Secrets = shell `.env` + `lookup('env',…)`.** `secrets/<app>.env` (gitignored,
  values single-quoted so bash `source` keeps `$`-strings like bcrypt hashes
  literal). `deploy.sh` does `set -a; source …; set +a` then runs Ansible;
  playbooks read `{{ lookup('env','KEY') }}`. **No Ansible Vault, no sops, no
  encryption** — deliberate single-user/simple-tools choice. The whole repo minus
  `secrets/*.env` is safe to push; secrets live only on the laptop (lose laptop →
  lose secrets; back them up).
- **Single source of truth, no duplication.** Every config/secret is defined
  once. Shared secrets are owned by one file and *cross-sourced*:
  - `CF_API_TOKEN` → `secrets/common.env` only (used by the `caddy` role).
  - `PUSHOVER_USER` / `PUSHOVER_TOKEN` → `secrets/tracker.env` only;
    `sentry/deploy.sh` also sources `tracker.env`.
  - `HUSKY_TRACCAR_USERNAME` / `_PASSWORD` / `_API_TOKEN` → `secrets/tracker.env`
    only (tracker *creates* that Traccar user); `husky/deploy.sh` sources it.
  - App-specific prefixes (`SENTRY_TRACCAR_`, `HUSKY_AUTH_`, `FORGE_AUTH_`) keep
    the cross-sourced env files collision-free.
- **Always deploy `main`** (v1: no commit pinning). `clone_repo` does
  `git clone --depth 1 git@github.com:ElgarsU/<repo>.git`.
- **Idempotent everywhere.** Markers (`.installed-version-*`, `.admin-replaced`),
  `creates:`, `WHERE NOT EXISTS`, `state: present`. Safe to re-run.
- **Don't reuse names across apps.** Each app's systemd unit / system user /
  secrets file is named after the app.
- **`enduro-data` group** is created by the `common` role (the single owner).
  Each app that needs it (`sentry`, `husky`) adds *its own* user with
  `append: true` **and asserts membership**. Never add another app's user from
  your role; never drop `append: true` (it would wipe the membership).

## The build model (per app)

`build.sh` (in each app repo) must produce `./dist/` + `./dist/MANIFEST`. Full
spec + reference scripts: `docs/build-sh-contract.md`. Summary:

| App | build.sh does | Where the real build runs |
|---|---|---|
| tracker | *(none)* | Traccar vendored zip fetched + SHA-verified **on the VPS** |
| sentry | Go cross-compile → `dist/sentry-linux-arm64` | control node (laptop) |
| husky | stage clean source → `dist/` | **on the VPS** (`npm ci`/`build` — native `better-sqlite3`) |
| discord-scraper | stage source → `dist/` | **on the VPS** (venv + pip) |
| forge | `npm ci && npm run build` → `dist/.output` | control node (no native deps) |
| prelander | copy static files → `dist/` | n/a (static) |
| honda | stage clean source → `dist/` | **on the VPS** (`npm ci`/`build` — native `better-sqlite3`) |

`enduro-tracking` is one repo holding two infra apps (tracker + sentry); its
single `build.sh` builds sentry. tracker needs no build.

## Cross-app contracts (must survive any change)

- **sentry depends on tracker:** Traccar must be up + the FMC880 device (IMEI
  `862129081248340`) registered before sentry deploys (sentry resolves the device
  id and links its read-only Traccar user). tracker pre-registers the device.
- **husky depends on tracker + sentry:** logs into Traccar as the read-only
  `husky` user (creds from `tracker.env`); reads/writes `/var/lib/sentry/state.db`
  via the `enduro-data` group.
- **Pushover flows to both** tracker (Traccar `notificator.pushover.*`) and sentry
  (`SENTRY_PUSHOVER_*`). One source: `tracker.env`.
- **Deploy order** (encoded in `setup.sh`): tracker → sentry → husky →
  discord-scraper → forge → prelander.

## Gotchas (preserved from the source repos — keep them)

These are also commented at the relevant code. Don't "clean them up."

1. **Traccar computed attributes — `attributes.get()` breaks alarms.** In
   `apps/tracker/ansible/playbook.yml`, expressions are the bare
   `io252 == 1 ? "powerCut" : null` form. The "null-safe"
   `attributes.get("io252") != null && …` form silences a harmless per-record
   WARN but **silently breaks alarm evaluation in Traccar 6.13.3** (alarm never
   fires). The bare form is the only one that works.
2. **Traccar timezone = JVM flag.** `traccar.service.override.j2` runs the JVM
   with `-Duser.timezone=Europe/Riga`, so logs AND `tc_positions.servertime` are
   Riga-local, **not UTC**. Anything reading Traccar timestamps must treat them as
   Riga-local (no UTC→local conversion). Changing the flag later creates a
   one-time discontinuity in stored timestamps.
3. **`notificator.types` must include `pushover`.** In `traccar.xml.j2`. Without
   it, `NotificatorManager.getNotificator("pushover")` throws "Failed to get
   notificator pushover" at alarm time — the default is only `web,mail,command`.
   Having the `.user`/`.token` keys alone is not enough.
4. **sentry SQLite 0644 hack.** SQLite hardcodes mode 0644 on create. For husky
   (in `enduro-data`) to write `state.db`, sentry runs with `UMask=002`
   (`sentry.service.j2`), `/var/lib/sentry` is setgid `2770`, and the daemon
   `chmod`s the DB to 0660 at startup (`EnsureSharedPerms` in `services/sentry/main.go`).
   All three are needed together.
5. **`enduro-data` `append: true`.** Adding a user to the group without
   `append: true` wipes their other supplementary groups. Each app role asserts
   its user's membership so a wipe is caught.
6. **Traccar v6 seeds no admin on Postgres.** tracker INSERTs the personal admin
   directly via SQL (the `/api/users` first-user path NPEs in 6.13.3). PBKDF2
   params (`PBKDF2WithHmacSHA1`, 1000 iters, 24-byte salt+hash) are hardcoded to
   match `Hashing.java` v6.13.3 — update in lockstep on a Traccar upgrade.
7. **`caddy validate` needs the CF token.** Every validate step does
   `set -a; source /etc/caddy/cloudflare.env; caddy validate …` because the
   Caddyfile references `{env.CF_API_TOKEN}`, unset in a bare shell.
8. **husky builds on the VPS.** `better-sqlite3` is a native module; a Mac build
   won't load on Linux. `build.sh` only stages source; `npm ci`/`npm run build`
   run on the box (with `HOME` pointed into the app dir since the `husky` user
   has no home).
9. **forge `STATE_DIR`.** The app falls back to `.` if `STATE_DIR` is unset.
   The systemd unit must set `Environment=STATE_DIR=/opt/forge/data`.
10. **`--check` artifacts.** Read-only verification commands have
    `check_mode: false` so dry-runs work; `uri` health-checks are skipped under
    `--check` and will "fail" the `until` — that's a check-mode artifact, not a
    real error. `ansible.posix.synchronize` may not fully honor `--check` — be
    cautious dry-running apps that rsync to the live box.

## What is NOT here

- **mission-control** (`git@github.com:ElgarsU/mission-control.git`, default
  branch `master`) is **not deployed by this repo.** It's a MacBook-side Go agent
  (launchd) + a not-yet-built VPS relay, with its own WireGuard VPN setup. Its
  Ansible Vault was removed during migration and its README/CLAUDE point here, but
  it has no `apps/mission-control/` entry. Revisit when `mc-relay` is built.

## Out-of-band (can't be automated)

- Hetzner **cloud firewall** (separate from ufw): allow `22/80/443/5027`; ICMP
  deliberately blocked. Caddy must be pre-installed before `setup.sh`.
- Cloudflare DNS records (orange/gray-cloud per `docs/vps-inventory.md`).
- `husky_traccar_api_token` is operator-generated via the Traccar UI after first
  deploy (not used by Ansible; stored in `tracker.env` for the app to read).
