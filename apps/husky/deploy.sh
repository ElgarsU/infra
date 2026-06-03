#!/usr/bin/env bash
# Deploy: husky (Nuxt 4 SSR maintenance + live-tracking dashboard).
#
# Source repo: husky. Its build.sh STAGES clean source into dist/ (no compile
# locally) because husky uses better-sqlite3 — a native module that must be
# built on the target. The playbook rsyncs dist/ to /opt/husky/app and runs
# `npm ci` + `npm run build` ON THE VPS (Linux/ARM64 native bindings).
#
# Secrets: secrets/husky.env (app auth/session + Traccar URL/device) plus
# secrets/tracker.env (the shared read-only Traccar user creds — single source).
# Depends on: tracker (Traccar user) + base roles (Node 20, enduro-data, Caddy).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files tracker husky        # tracker → HUSKY_TRACCAR_USERNAME/PASSWORD/API_TOKEN
clone="$(clone_repo husky)"
build_clone "$clone"
ansible_app husky -e "dist_dir=$clone/dist" "$@"
