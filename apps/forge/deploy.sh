#!/usr/bin/env bash
# Deploy: forge (Nuxt 3 SPA + Nitro server — physical + moto training tracker).
#
# Source repo: forge (git@github.com:ElgarsU/forge.git). No native modules, so
# build.sh runs `npm ci && npm run build` LOCALLY and stages the .output bundle
# into dist/.output. The playbook rsyncs it to /opt/forge/.output and restarts
# the forge systemd service.
#
# Secret: secrets/forge.env → FORGE_AUTH_HASH (the single-user login hash,
# migrated out of the app's source code into an env var).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files forge
clone="$(clone_repo forge)"
build_clone "$clone"
ansible_app forge -e "dist_dir=$clone/dist" "$@"
