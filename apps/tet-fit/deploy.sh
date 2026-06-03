#!/usr/bin/env bash
# Deploy: tet-fit (Nuxt 3 SPA + Nitro server — TET 290km training tracker).
#
# Source repo: tet-fit (git remote tet-fit; local dir is tet-training). No
# native modules, so build.sh runs `npm ci && npm run build` LOCALLY and stages
# the .output bundle into dist/.output. The playbook rsyncs it to
# /opt/tet-training/.output and restarts the tet-training systemd service.
#
# NOTE: the systemd unit, app dir, and service are named "tet-training"
# (preserved from the original deploy) while the infra app / repo is "tet-fit".
#
# Secret: secrets/tet-fit.env → TET_AUTH_HASH (the single-user login hash,
# migrated out of the app's source code into an env var).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files tet-fit
clone="$(clone_repo tet-fit)"
build_clone "$clone"
ansible_app tet-fit -e "dist_dir=$clone/dist" "$@"
