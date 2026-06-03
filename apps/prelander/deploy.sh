#!/usr/bin/env bash
# Deploy: prelander (static elgars.eu landing page).
#
# Source repo: elgars-eu-prelander. build.sh stages the static files (index.html
# + icons) into dist/. The playbook copies them to /var/www/elgars-prelander
# and renders the Caddy file_server site for elgars.eu + www.elgars.eu.
#
# No systemd unit, no app secrets — the Cloudflare DNS-01 token used for TLS is
# the shared one written to /etc/caddy/cloudflare.env by the base `caddy` role.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

clone="$(clone_repo elgars-eu-prelander)"
build_clone "$clone"
ansible_app prelander -e "dist_dir=$clone/dist" "$@"
