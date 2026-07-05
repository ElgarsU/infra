# `build.sh` contract

Every app repo provides a `build.sh` at its repo root. The infra repo doesn't
care *how* an app builds — Go, Node, Python, static — it just clones the app's
`main`, runs `build.sh`, and consumes `./dist/`.

## The contract

`build.sh` must:

1. **Run from the repo root, with no arguments.** (`infra` runs `bash build.sh`
   inside a fresh clone.)
2. **Produce deployable artifacts in `./dist/`.** This is the directory infra
   copies from. What goes in it is app-specific (a binary, a built bundle, or
   just staged source — see per-app notes).
3. **Write `./dist/MANIFEST`** — a plain-text listing of what it produced.
   Helps the playbook/debugging know what to copy. `infra`'s `build_clone`
   helper *fails the deploy* if `dist/MANIFEST` is missing.
4. **Exit 0 on success, non-zero on failure.**
5. **Be idempotent** — re-running (it `rm -rf dist` first) doesn't break.
6. **Self-contain its build deps**, or assume a documented base toolchain
   (Go / Node / Python — see per-app "needs").

The deploy flow (`apps/<app>/deploy.sh`): load secrets → `git clone --depth 1`
the app's `main` → `bash build.sh` → `ansible-playbook … -e dist_dir=<clone>/dist`
→ playbook copies artifacts → temp clone is cleaned up.

## Two build shapes

Because the VPS is ARM64 Linux and the control node is an ARM64 Mac, apps fall
into two shapes:

- **Build locally, copy the artifact.** Works when the artifact is
  platform-independent or cross-compiled: `forge` (Nuxt bundle, no native
  deps) and `sentry` (Go `CGO_ENABLED=0` cross-compile).
- **Stage source, build on the VPS.** Required when a native module must be
  compiled for the target: `husky` (`better-sqlite3`). Here `build.sh` just
  rsyncs clean source into `dist/`; the playbook runs `npm ci`/`npm run build`
  on the box. `discord-scraper` is similar (venv built on the VPS).

### tracker (the exception)

`tracker` has **no `build.sh` and no clone/build step.** Traccar is a vendored
upstream release; `apps/tracker/ansible/playbook.yml` downloads + SHA256-verifies
the pinned zip *on the VPS* (cached, idempotent). It's the one app whose
artifact is fetched server-side rather than built from a repo and copied.

The `enduro-tracking` repo (which holds both tracker config and sentry source)
ships a `build.sh` that builds **sentry** — that's the only buildable code there.

## Per-app `build.sh` reference implementations

These are the canonical scripts committed to each app repo (added during the
migration's step 7). Reproduced here as the source of truth.

### `enduro-tracking/build.sh` — builds **sentry**
> Needs: Go (control node). Output: `dist/sentry-linux-arm64` (static arm64).
```bash
#!/usr/bin/env bash
# Build the sentry service for deployment by the infra repo.
# Produces a static linux/arm64 binary — CGO_ENABLED=0 keeps modernc.org/sqlite
# pure-Go so it's a true single-file deploy. The `tracker` infra app needs no
# build (Traccar is vendored + fetched on the VPS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
cd "$ROOT/services/sentry"
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
  go build -trimpath -ldflags=-s -ldflags=-w -o "$DIST/sentry-linux-arm64" .
{
  echo "service: sentry"
  echo "binary:  sentry-linux-arm64"
  echo "go:      $(go version)"
  echo "sha256:  $(shasum -a 256 "$DIST/sentry-linux-arm64" | awk '{print $1}')"
} > "$DIST/MANIFEST"
echo "Built $DIST/sentry-linux-arm64"
```

### `husky/build.sh` — stage source (build on VPS)
> Needs: rsync. Output: clean source tree in `dist/` (VPS runs npm ci + build).
```bash
#!/usr/bin/env bash
# Stage husky source for deploy. husky builds ON THE VPS because better-sqlite3
# compiles a native .node binary — a Mac build won't load on Linux. So this
# just produces a clean source tree; the playbook runs npm ci + npm run build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
rsync -a \
  --exclude='.git' --exclude='node_modules' --exclude='.output' --exclude='.nuxt' \
  --exclude='.data' --exclude='local-snapshots' --exclude='dist' \
  --exclude='.DS_Store' --exclude='.claude' \
  "$ROOT/" "$DIST/"
( cd "$DIST" && find . -type f ! -name MANIFEST | sed 's#^\./##' | sort ) > "$DIST/MANIFEST"
echo "Staged $(wc -l < "$DIST/MANIFEST") files into $DIST"
```

### `forge/build.sh` — build locally
> Needs: Node 20. Output: `dist/.output` (Nitro server bundle).
```bash
#!/usr/bin/env bash
# Build the forge Nuxt bundle locally (no native deps) and stage .output.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
npm ci
npm run build
[ -f .output/server/index.mjs ] || { echo "build failed: .output/server/index.mjs missing" >&2; exit 1; }
DIST="$ROOT/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
cp -a .output "$DIST/.output"
( cd "$DIST" && find .output -type f | sort ) > "$DIST/MANIFEST"
echo "Built $DIST/.output"
```

### `discord-scraper/build.sh` — stage source (venv on VPS)
> Needs: rsync. Output: clean source + requirements.txt in `dist/`.
```bash
#!/usr/bin/env bash
# Stage discord-scraper source. The venv + pip install happen on the VPS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
rsync -a \
  --exclude='.git' --exclude='.venv' --exclude='dist' --exclude='__pycache__' \
  --exclude='.env' --exclude='data' --exclude='.DS_Store' --exclude='.claude' \
  "$ROOT/" "$DIST/"
( cd "$DIST" && find . -type f ! -name MANIFEST | sed 's#^\./##' | sort ) > "$DIST/MANIFEST"
echo "Staged $(wc -l < "$DIST/MANIFEST") files into $DIST"
```

### `elgars-eu-prelander/build.sh` — stage static files
> Needs: nothing. Output: the static files in `dist/`.
```bash
#!/usr/bin/env bash
# Stage the static prelander site (no build step).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
for f in index.html favicon.svg favicon.ico apple-touch-icon.png icon-192.png icon-512.png; do
  [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$DIST/$f"
done
( cd "$DIST" && find . -type f ! -name MANIFEST | sed 's#^\./##' | sort ) > "$DIST/MANIFEST"
echo "Staged $(wc -l < "$DIST/MANIFEST") files into $DIST"
```
