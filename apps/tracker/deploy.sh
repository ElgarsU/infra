#!/usr/bin/env bash
# Deploy: tracker (Traccar GPS server).
#
# Tracker is the ONE app with no clone/build step: Traccar is a vendored
# upstream release, downloaded + SHA-verified ON THE VPS by the playbook
# (cached, idempotent). There is no app source to build here. The sentry
# service (same enduro-tracking repo) is what build.sh in that repo builds.
#
# Reads secrets from secrets/tracker.env (Postgres, admin, Pushover, husky
# Traccar user). Depends on base roles (postgres, caddy) — run ./setup.sh on a
# fresh box, or ensure site.yml has run.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files tracker
ansible_app tracker "$@"
