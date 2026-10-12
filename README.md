# infra

Single source of truth for deploying every app to my Hetzner VPS. Each app repo
holds only application code + `build.sh`; **all** deploy logic, Ansible, and
secrets live here.

- **VPS:** Hetzner CAX11 (ARM64), Ubuntu 24.04, `89.167.98.246`, Helsinki.
- **Apps:** `tracker` (Traccar), `sentry`, `husky`, `discord-scraper`,
  `forge`, `prelander`, `honda`, `kp`.

## Quick start

> **Always `git pull` this infra repo first.** Deploys run from your *local*
> checkout of infra (scripts, Ansible, secrets templates) — an out-of-date
> checkout deploys stale config. Pull before every deploy:
>
> ```bash
> git -C "$(git rev-parse --show-toplevel)" pull --ff-only
> ```

```bash
# Deploy one app (clone its main → build.sh → Ansible)
./deploy.sh husky

# Dry-run against the live VPS (no changes)
./deploy.sh tracker --check --diff

# Provision a FRESH VPS from zero (base roles + every app, in dependency order)
./setup.sh
```

First time on a new laptop: copy your `secrets/*.env` files into `secrets/`
(they're gitignored — see below), then deploy.

## Layout

```
deploy.sh              ./deploy.sh <app> — dispatcher
setup.sh               full fresh-VPS rebuild (site.yml + every app)
ansible/
  site.yml             base provisioning: roles common → caddy → postgres
  roles/{common,caddy,postgres}/
apps/
  _lib/deploy-common.sh   shared clone→build→ansible helpers
  <app>/deploy.sh         per-app orchestrator
  <app>/ansible/playbook.yml + templates/
secrets/
  <app>.env            real values — GITIGNORED, lives only on the laptop
  <app>.env.example    committed template with placeholders
docs/
  vps-inventory.md     live ports/users/units/deps for the whole box
  adding-a-new-app.md  step-by-step for app #7
  build-sh-contract.md what build.sh must do (+ per-app reference scripts)
CLAUDE.md              architecture, conventions, gotchas (read this)
```

## How a deploy works

First, **`git pull` this infra repo** so your local checkout matches the remote
(deploys run from local files — stale checkout, stale deploy). Then
`./deploy.sh <app>` runs `apps/<app>/deploy.sh`, which:
1. sources `secrets/<app>.env` (+ any shared env files) into the environment;
2. clones the app repo's **`main`** into a temp dir (v1: always main, no pinning);
3. runs the app's `build.sh` → `./dist/`;
4. runs `ansible-playbook apps/<app>/ansible/playbook.yml -e dist_dir=…`, which
   copies artifacts, renders config/systemd from secrets, restarts the service;
5. cleans up the temp clone. Any failure exits non-zero.

`tracker` is the exception — no clone/build; Traccar is fetched + SHA-verified
on the VPS. See `docs/build-sh-contract.md`.

## Secrets

Plain `KEY='value'` files in `secrets/`, **gitignored** (`secrets/.gitignore`
allows only `*.env.example`). Deploy scripts `source` them; playbooks read them
via `lookup('env', …)`. No Ansible Vault, no sops, no encryption — by deliberate
choice (single user, simple tools).

> **The trade-off:** the whole repo minus `secrets/*.env` is safe to push to
> GitHub. The real secrets live only on the laptop. **Lose the laptop → lose the
> secrets.** Back up `secrets/` somewhere safe (password manager / encrypted
> drive). After a clean checkout, copy `secrets/*.env` back before deploying.

To populate from scratch: `cp secrets/<app>.env.example secrets/<app>.env` and
fill in the values. See each `.example` for how to generate each value.

## Notes

- Idempotent throughout — every `deploy.sh` and role is safe to re-run.
- Always deploys `main` (mission-control's repo is `master`, but it isn't
  deployed here — see CLAUDE.md).
- Don't run `./setup.sh` against the live box casually; it converges base host
  state + every app. For day-to-day use `./deploy.sh <app>`.
