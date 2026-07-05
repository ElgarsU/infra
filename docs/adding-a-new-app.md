# Adding a new app (app #7)

Step-by-step for adding another app to the VPS via this infra repo. Follow it
top to bottom; it encodes the conventions so you don't have to re-derive them.

Assume the new app is called **`foo`**, repo `git@github.com:ElgarsU/foo.git`,
a Node server on `127.0.0.1:3002` behind `foo.elgars.eu`. Adjust to taste.

## 1. Pick the slots

- **Port:** next free localhost port in the 3000-block → `3002` (3000=forge,
  3001=husky). Bind `127.0.0.1` only.
- **Subdomain:** `foo.elgars.eu`. Create a Cloudflare DNS record, **orange-cloud**,
  → `89.167.98.246`.
- **System user:** `foo` (dedicated, `nologin`, `/opt/foo`).
- **systemd unit:** `foo.service`.

Add the row to `docs/vps-inventory.md` now (so the doc never lags).

## 2. Secrets

```bash
cp secrets/foo.env.example secrets/foo.env   # after you write the example
```
- Create `secrets/foo.env.example` with placeholder `KEY='PASTE_…'` lines and
  comments. Commit it.
- Put real values in `secrets/foo.env` (gitignored, single-quoted so `source`
  keeps `$`-strings literal).
- If `foo` needs a value another app owns (e.g. Pushover), don't duplicate —
  have `foo/deploy.sh` also source that app's env file (see how `sentry` sources
  `tracker.env`).

## 3. App-side `build.sh`

In the **app repo**, add `build.sh` at the root per `docs/build-sh-contract.md`:
produce `./dist/` + `./dist/MANIFEST`, exit non-zero on failure, idempotent.
- Native deps that must build on the VPS → stage source into `dist/`, build on
  the box (like husky).
- No native deps → build locally, copy the bundle (like forge).

## 4. `apps/foo/deploy.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../_lib/deploy-common.sh"

load_env_files foo                 # + any shared env files this app needs
clone="$(clone_repo foo)"          # clones git@github.com:ElgarsU/foo.git main
build_clone "$clone"               # runs build.sh, asserts dist/ + MANIFEST
ansible_app foo -e "dist_dir=$clone/dist" "$@"
```
`chmod +x apps/foo/deploy.sh`.

## 5. `apps/foo/ansible/playbook.yml`

Use an existing app as a template (`husky` for "build on host", `forge` for
"copy built bundle", `prelander` for static). The skeleton:

```yaml
- name: foo
  hosts: vps
  become: true
  gather_facts: true
  vars:
    foo_secret: "{{ lookup('env', 'FOO_SECRET') }}"
    foo_port: 3002
    foo_user: foo
    foo_dir: /opt/foo
  pre_tasks:
    - name: Assert staged artifacts were passed
      ansible.builtin.assert:
        that: [ "dist_dir is defined" ]
      delegate_to: localhost
      become: false
    - name: Assert base caddy role has run
      ansible.builtin.stat: { path: /etc/caddy/cloudflare.env }
      register: cf_env
    - ansible.builtin.assert:
        that: [ "cf_env.stat.exists" ]
        fail_msg: "Run ./setup.sh (or ansible/site.yml) first."
    - name: Validate secrets
      ansible.builtin.assert:
        that: [ "foo_secret | length > 0", "'PASTE' not in foo_secret" ]
  tasks:
    - name: Create foo system user
      ansible.builtin.user:
        name: "{{ foo_user }}"
        system: true
        shell: /usr/sbin/nologin
        home: "{{ foo_dir }}"
        create_home: false
    # … copy artifacts from {{ dist_dir }}, render .env (EnvironmentFile),
    #   install foo.service, render the Caddy site, restart, health-check …
    - name: Render foo.elgars.eu Caddy site
      ansible.builtin.template:
        src: caddy.foo.j2
        dest: /etc/caddy/sites.d/foo.elgars.eu.caddy
        mode: "0644"
      register: foo_site
    - name: Validate Caddy + reload
      when: foo_site.changed
      ansible.builtin.shell:
        cmd: |
          set -a; source /etc/caddy/cloudflare.env
          caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
          systemctl reload caddy
        executable: /bin/bash
      changed_when: true
```

**systemd hardening defaults** for the unit template:
```ini
[Service]
User=foo
Group=foo
EnvironmentFile=/opt/foo/.env
ExecStart=/usr/bin/node /opt/foo/.output/server/index.mjs
Restart=always
RestartSec=5
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
ReadWritePaths=/opt/foo/data
```

**Caddy site template** (`apps/foo/ansible/templates/caddy.foo.j2`):
```caddy
foo.elgars.eu {
    tls { dns cloudflare {env.CF_API_TOKEN} }
    encode gzip
    import security_headers
    reverse_proxy 127.0.0.1:{{ foo_port }}
}
```

## 6. Wire into `setup.sh`

Add `foo` to the `APPS=(…)` array in `setup.sh`, in the right dependency
position (independent apps go after the tracker→sentry→husky chain).

## 7. Validate, then deploy

```bash
bash -n apps/foo/deploy.sh
ansible-playbook --syntax-check -i ansible/inventory.yml apps/foo/ansible/playbook.yml
# dry run once build.sh is pushed to the app repo:
./deploy.sh foo --check --diff
./deploy.sh foo
```

## 8. Clean the app repo

The app repo holds **only** application code + `build.sh`. No deploy logic, no
Ansible, no secrets. Update its `README.md` + `CLAUDE.md` to point at this infra
repo (`git@github.com:ElgarsU/infra.git`).

## 9. Update docs

- `docs/vps-inventory.md` — the app row + any new shared dependency.
- `CLAUDE.md` — if the app introduces a new gotcha or cross-app contract.
