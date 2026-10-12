#!/usr/bin/env bash
# Deploy: kp (Next.js booking / client management app for a gym trainer).
#
# Source repo: kp. Its build.sh STAGES clean source into dist/ (no compile
# locally) because kp uses better-sqlite3 — a native module that must be
# built on the target. The playbook rsyncs dist/ to /opt/kp/app and runs
# `npm ci` + `npm run build` ON THE VPS (Linux/ARM64 native bindings).
#
# Standalone app: no cross-app deps — just the base roles (Node 20, Caddy).
# Secrets: secrets/kp.env (trainer login password).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files kp
clone="$(clone_repo kp)"
build_clone "$clone"
ansible_app kp -e "dist_dir=$clone/dist" "$@"
