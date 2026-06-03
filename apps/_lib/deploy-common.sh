#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# Shared helpers for every apps/<app>/deploy.sh.
#
# Source this at the top of an app deploy script:
#     source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"
#
# Provides:
#   log / warn / die        — consistent output
#   load_env_files a b ...   — export vars from secrets/<a>.env, secrets/<b>.env
#   clone_repo <repo>        — git clone main into a temp dir, echo the path
#   build_clone <dir>        — run ./build.sh in <dir>, assert dist/ + MANIFEST
#   ansible_app <app> [-e …] — ansible-playbook apps/<app>/ansible/playbook.yml
#
# Every clone is registered for cleanup on exit (success or failure).
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

# infra repo root = two levels up from apps/_lib/
INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_DIR="$INFRA_ROOT/secrets"
export ANSIBLE_CONFIG="$INFRA_ROOT/ansible/ansible.cfg"
INVENTORY="$INFRA_ROOT/ansible/inventory.yml"

# GitHub org — every app repo is git@github.com:ElgarsU/<repo>.git, deployed
# from main (v1: no commit pinning).
GIT_ORG="git@github.com:ElgarsU"

_CLEANUP_DIRS=()
_cleanup() { for d in "${_CLEANUP_DIRS[@]:-}"; do [ -n "${d:-}" ] && rm -rf "$d"; done; }
trap _cleanup EXIT

log()  { printf '\033[1;34m[deploy]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[deploy]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[deploy] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# load_env_files <name> [<name> ...]
# Sources secrets/<name>.env files in order, exporting all their vars into the
# environment (so playbooks can read them via lookup('env', 'KEY')). Fails if a
# file is missing or still contains a PASTE_ placeholder.
load_env_files() {
  local name f
  for name in "$@"; do
    f="$SECRETS_DIR/${name}.env"
    [ -f "$f" ] || die "missing secrets file: $f
  → copy ${f}.example to ${f} and fill in real values."
    if grep -q 'PASTE_' "$f"; then
      die "secrets file still has PASTE_ placeholders: $f"
    fi
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
  done
}

# clone_repo <repo-name>  → echoes the temp clone path
# Clones the default branch (main) shallowly. v1 deploys main, no pinning.
clone_repo() {
  local repo="$1" dir
  require_cmd git
  dir="$(mktemp -d "${TMPDIR:-/tmp}/infra-${repo}.XXXXXX")"
  _CLEANUP_DIRS+=("$dir")
  log "Cloning ${GIT_ORG}/${repo}.git (main) → $dir" >&2
  git clone --depth 1 --quiet "${GIT_ORG}/${repo}.git" "$dir" \
    || die "git clone failed for $repo"
  echo "$dir"
}

# build_clone <clone-dir>
# Runs the app's build.sh (the app's responsibility) and asserts the contract:
# dist/ exists and dist/MANIFEST was written.
build_clone() {
  local dir="$1"
  [ -x "$dir/build.sh" ] || [ -f "$dir/build.sh" ] || die "no build.sh at repo root of $dir"
  log "Running build.sh in $dir"
  ( cd "$dir" && bash build.sh ) || die "build.sh failed"
  [ -d "$dir/dist" ]          || die "build.sh did not produce ./dist/"
  [ -f "$dir/dist/MANIFEST" ] || die "build.sh did not write ./dist/MANIFEST"
  log "Build OK — dist/ contents:"
  ( cd "$dir/dist" && find . -maxdepth 2 -type f | sed 's/^/    /' )
}

# ansible_app <app> [extra ansible-playbook args...]
ansible_app() {
  local app="$1"; shift
  local playbook="$INFRA_ROOT/apps/${app}/ansible/playbook.yml"
  [ -f "$playbook" ] || die "no playbook for app '$app' at $playbook"
  require_cmd ansible-playbook
  log "ansible-playbook $app"
  ansible-playbook -i "$INVENTORY" "$playbook" "$@"
}
