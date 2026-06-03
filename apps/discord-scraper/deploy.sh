#!/usr/bin/env bash
# Deploy: discord-scraper (ss.com Husqvarna FE listings → Discord, 4×/day).
#
# Source repo: discord-scraper (Python). build.sh stages source into dist/
# (no compile). The playbook rsyncs it to /opt/discord-scraper/app, builds a
# venv + pip-installs ON THE VPS, and installs a systemd service + timer.
# No web surface, no inbound ports.
#
# Secrets: secrets/discord-scraper.env (the Discord webhook).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files discord-scraper
clone="$(clone_repo discord-scraper)"
build_clone "$clone"
ansible_app discord-scraper -e "dist_dir=$clone/dist" "$@"
