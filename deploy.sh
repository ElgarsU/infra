#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# Top-level deploy dispatcher.
#
#   ./deploy.sh <app> [extra ansible-playbook args...]
#
# Extra args after <app> are forwarded to ansible-playbook, e.g.:
#   ./deploy.sh tracker --check --diff
#
# Each app lives in apps/<app>/ with its own deploy.sh that does:
#   1. load secrets/<app>.env (+ any shared env files)
#   2. clone the app repo's main, run its build.sh → dist/   (most apps)
#   3. ansible-playbook apps/<app>/ansible/playbook.yml
#   4. clean up the temp clone
#
# Run ./setup.sh to provision a fresh VPS (base roles + every app in order).
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$INFRA_ROOT/apps"

usage() {
  echo "Usage: ./deploy.sh <app> [extra ansible-playbook args...]"
  echo
  echo "Available apps:"
  for d in "$APPS_DIR"/*/; do
    name="$(basename "$d")"
    [ "$name" = "_lib" ] && continue
    [ -f "$d/deploy.sh" ] && echo "  $name"
  done
  exit "${1:-1}"
}

[ $# -ge 1 ] || usage 1
app="$1"; shift
[ "$app" = "-h" ] || [ "$app" = "--help" ] && usage 0

deploy="$APPS_DIR/$app/deploy.sh"
[ -f "$deploy" ] || { echo "Unknown app: $app" >&2; usage 1; }

# Forward any remaining args (e.g. --check --diff) to the app's deploy.sh,
# which passes them through to ansible-playbook.
exec bash "$deploy" "$@"
