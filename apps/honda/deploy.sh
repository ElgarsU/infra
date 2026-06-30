#!/usr/bin/env bash
# Deploy: honda (Nuxt 4 SSR maintenance log for a Honda CRF300L).
#
# Source repo: honda. Its build.sh STAGES clean source into dist/ (no compile
# locally) because honda uses better-sqlite3 — a native module that must be
# built on the target. The playbook rsyncs dist/ to /opt/honda/app and runs
# `npm ci` + `npm run build` ON THE VPS (Linux/ARM64 native bindings).
#
# Standalone app: no Traccar, no enduro-data group, no cross-app deps — just
# the base roles (Node 20, Caddy). Secrets: secrets/honda.env (app auth/session).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files honda
clone="$(clone_repo honda)"
build_clone "$clone"
ansible_app honda -e "dist_dir=$clone/dist" "$@"
