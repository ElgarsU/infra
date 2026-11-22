#!/usr/bin/env bash
# Deploy: now (calm personal project planner at now.elgars.eu).
#
# Source repo: now. Its build.sh runs the tests, cross-compiles the static
# linux/arm64 Go API (pure-Go SQLite, no CGO) and builds the React frontend
# (needs Go + Node on the control node). The playbook copies the binary to
# /opt/now/now and the frontend to /var/www/now.
#
# Standalone app: no cross-app deps — just the base roles (Caddy).
# Secrets: secrets/now.env (NOW_PASSWORD_HASH, a PBKDF2 hash — never the password).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files now
clone="$(clone_repo now)"
build_clone "$clone"
ansible_app now -e "dist_dir=$clone/dist" "$@"
