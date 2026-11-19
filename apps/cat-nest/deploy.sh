#!/usr/bin/env bash
# Deploy: cat-nest (read-only Viessmann Vitodens boiler logger, polls every 2 min,
# and the read-only eWeLink room-sensor logger cat-nest-ewelink, every 5 min).
#
# Source repo: cat-nest (Python, stdlib only). build.sh runs the unit tests and
# stages the `catnest` package into dist/ (no compile, no venv). The playbook
# rsyncs it to /opt/cat-nest/app, renders the env file + systemd unit + CLI
# wrapper, and serves the status page at nest.elgars.eu/<secret path>/vitodens-status.
#
# Secrets: secrets/cat-nest.env (VIESSMANN_CLIENT_ID, HC_PING_URL, CATNEST_STATUS_PATH,
# EWELINK_APP_ID, EWELINK_APP_SECRET, EWELINK_REGION, HC_PING_URL_EW).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files cat-nest
clone="$(clone_repo cat-nest)"
build_clone "$clone"
ansible_app cat-nest -e "dist_dir=$clone/dist" "$@"
