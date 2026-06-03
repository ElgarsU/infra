#!/usr/bin/env bash
# Deploy: sentry (Traccar alarm watcher + Pushover emergency dispatcher).
#
# Source repo: enduro-tracking (same repo as tracker). Its build.sh
# cross-compiles the static linux/arm64 Go binary into dist/sentry-linux-arm64
# (needs Go on the control node). This deploy.sh clones main, builds, and the
# playbook copies the binary to /opt/sentry/sentry.
#
# Secrets: secrets/sentry.env (sentry Traccar user) + secrets/tracker.env
# (shared Pushover creds — single source of truth lives in tracker.env).
# Depends on: tracker (Traccar + device registered) and the base roles
# (enduro-data group from common).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files tracker sentry        # tracker first → PUSHOVER_*; sentry → SENTRY_TRACCAR_*
clone="$(clone_repo enduro-tracking)"
build_clone "$clone"
ansible_app sentry -e "dist_dir=$clone/dist" "$@"
