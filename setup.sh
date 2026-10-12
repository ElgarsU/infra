#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# Provision a FRESH VPS from zero into a fully-running system with every app.
#
#   ./setup.sh
#
# This is the "rebuild from scratch" / disaster-recovery command. It:
#   1. Runs base VPS provisioning (ansible/site.yml): common + caddy + postgres
#   2. Deploys every app via its own deploy.sh, in dependency order:
#        tracker → sentry → husky → discord-scraper → forge → prelander
#   3. Stops on the FIRST failure with a clear message.
#
# ⚠️  NOT for routine use against the LIVE VPS — it converges base host state
#     (ufw, sshd, Caddy refactor) and every app at once. For day-to-day single
#     app deploys use ./deploy.sh <app>. Intended for: a brand-new VPS, or
#     after destructive recovery. It IS idempotent, so re-running is safe, but
#     run it knowingly.
#
# Prerequisites on a fresh VPS (out-of-band, can't be automated from here):
#   • Ubuntu 24.04 ARM64, root SSH key access (ssh root@<ip>)
#   • Caddy installed (Ubuntu caddy package) — provides caddy.service
#   • Hetzner cloud firewall: inbound 22, 80, 443, 5027/tcp, 51820/udp;
#     ICMP blocked. DNS (Cloudflare) per docs/vps-inventory.md.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INFRA_ROOT"

export ANSIBLE_CONFIG="$INFRA_ROOT/ansible/ansible.cfg"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1;36m══ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Apps in dependency order. tracker provides Traccar + Postgres `traccar` DB;
# sentry depends on tracker; husky depends on tracker (Traccar) + sentry
# (enduro-data group). The rest are independent (honda and kp are fully standalone).
APPS=(tracker sentry husky discord-scraper forge prelander honda kp)

step "Base VPS provisioning (ansible/site.yml)"
# CF_API_TOKEN for the caddy role comes from secrets/common.env.
[ -f "$INFRA_ROOT/secrets/common.env" ] || die "missing secrets/common.env (copy from secrets/common.env.example)"
set -a; # shellcheck disable=SC1091
source "$INFRA_ROOT/secrets/common.env"; set +a
ansible-playbook -i "$INFRA_ROOT/ansible/inventory.yml" "$INFRA_ROOT/ansible/site.yml" \
  || die "base provisioning (site.yml) failed — fix and re-run before deploying apps"

for app in "${APPS[@]}"; do
  step "Deploying app: $app"
  bash "$INFRA_ROOT/deploy.sh" "$app" \
    || die "deploy of '$app' failed — stopping. Fix it, then re-run ./setup.sh (idempotent) or ./deploy.sh $app."
done

step "Done"
bold "All base roles + ${#APPS[@]} apps deployed: ${APPS[*]}"
echo "See docs/vps-inventory.md for the live layout."
