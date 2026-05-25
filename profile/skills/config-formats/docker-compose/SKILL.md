---
name: docker-compose
description: "Docker Compose files (compose.yaml, docker-compose.yml, docker-compose.*.yml). Use when the operator mentions Docker Compose, has a YAML file with `services:`, `networks:`, `volumes:` top-level keys, or asks to edit container service definitions. Security-dense: environment / env_file may contain secrets; volume mounts cross host/container boundaries; cap_add and privileged escalate runtime privileges."
version: 1.0.0
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [config-format, docker, compose, container, yaml]
    related_skills: []
  fofoconfig:
    format: docker_compose
    file_globs:
      - "**/compose.yaml"
      - "**/compose.yml"
      - "**/docker-compose.yaml"
      - "**/docker-compose.yml"
      - "**/docker-compose.*.yml"
      - "**/docker-compose.*.yaml"
    discovery_commands: ["docker compose version", "docker compose config --quiet"]
    validator: "docker compose -f <file> config --quiet"
    syntax_kind: yaml
    secret_keys_caution:
      - environment
      - env_file
      - secrets
      - configs  # may reference secret files
      - extra_hosts  # internal hostnames are PII
---

# Docker Compose

## Format overview
YAML. Top-level keys (Compose Specification v1+): `services`, `networks`, `volumes`, `configs`, `secrets`, plus optional `name`, `include`. The legacy `version:` field (e.g. `version: "3.8"`) is **ignored by modern `docker compose`** (V2 plugin) and warns. Compose V1 (`docker-compose` standalone Python tool) is deprecated.

Each service maps a service name to a definition: image/build, ports, env, volumes, depends_on, etc.

## File locations
- **Conventional names** (auto-detected by `docker compose` in current dir): `compose.yaml` > `compose.yml` > `docker-compose.yaml` > `docker-compose.yml`.
- **Overrides:** `compose.override.yaml` auto-loads on top of `compose.yaml` (per the spec). Custom files via `-f file1 -f file2` (later wins for scalars, merges for lists).
- **Per-env split:** common pattern is `docker-compose.yml` (base) + `docker-compose.prod.yml` (overrides), invoked as `docker compose -f docker-compose.yml -f docker-compose.prod.yml up`.

## Top-level structure
```yaml
name: myapp                                # project name (alternative to -p / COMPOSE_PROJECT_NAME)

services:
  web:
    image: nginx:1.27-alpine               # pin to specific tags; never :latest in prod
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:80"                # bind to loopback; "8080:80" without IP binds to 0.0.0.0
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - web-data:/var/www
    environment:
      NGINX_HOST: ${NGINX_HOST:-localhost} # interpolated from .env or shell env at compose time
    env_file:
      - .env                               # values injected at runtime
    depends_on:
      api:
        condition: service_healthy

  api:
    build: ./api
    environment:
      DATABASE_URL: postgres://app:${DB_PASS}@db:5432/app   # [SECRET-ADJACENT]
    secrets:
      - source: api_jwt_secret
        target: jwt_secret                 # /run/secrets/jwt_secret in the container
    healthcheck:
      test: ["CMD", "curl", "-fs", "http://localhost:3000/healthz"]
      interval: 10s; timeout: 3s; retries: 3; start_period: 30s

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER_FILE: /run/secrets/db_user
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password     # prefer _FILE-suffixed vars
    volumes:
      - db-data:/var/lib/postgresql/data

volumes:
  web-data:
  db-data:

secrets:
  api_jwt_secret:
    file: ./secrets/jwt_secret             # plaintext file on host; refer via /run/secrets
  db_user:
    file: ./secrets/db_user
  db_password:
    file: ./secrets/db_password
```

## Common keys (security-relevant first)

| Key | Notes |
|---|---|
| `environment` | Map or list. Values **interpolated at compose-parse time** (`${VAR}` substituted from `.env` or shell). Visible in `docker compose config` output and image metadata. **DON'T put real secrets here for production.** Suitable for non-secret config. |
| `env_file` | Path(s) to env files. Loaded at container start; NOT interpolated at compose time. Better than `environment` for secrets but still injected as plain env vars (visible in `/proc/<pid>/environ` to anything with access). |
| `secrets` (top-level + per-service) | Mounts a secret as a file inside the container at `/run/secrets/<name>` (default; `target:` to override). Best practice for secrets — files have stricter access patterns than env vars. Pair with the postgres/redis/etc. `*_FILE` env conventions. |
| `volumes` | `host:container[:ro|rw|z|Z]`. **Bind mounts (`./path:/x`) cross the host/container boundary** — a container with `:rw` on `/etc` from host is host-root-equivalent. Named volumes (declared in top-level `volumes:`) are docker-managed. |
| `ports` | `host:container` exposes a host port. **`"8080:80"` binds 0.0.0.0:8080** (all interfaces). Prefix with `127.0.0.1:` to bind loopback only. Recommend explicit binding for any non-public service. |
| `network_mode: host` | Container shares host's network namespace — bypasses port mapping and isolation. Avoid unless required (e.g., low-latency networking). |
| `privileged: true` | Container gets ALL Linux capabilities and access to host devices. **Equivalent to root on host.** Almost never needed. |
| `cap_add` / `cap_drop` | Linux capabilities. `cap_drop: [ALL]` + `cap_add: [NET_BIND_SERVICE]` is a hardening pattern. |
| `security_opt` | `no-new-privileges:true` blocks setuid escalation inside container. `apparmor=<profile>`, `seccomp=<file>` apply MAC/syscall filters. |
| `read_only: true` | Mount container root fs read-only. Pair with explicit `tmpfs:` for writable scratch. Hardening win. |
| `user` | Run container process as specific UID/GID. Strings like `"1000:1000"` or `"appuser"`. Avoid running as root inside container when possible. |
| `restart` | `no`/`always`/`on-failure[:max]`/`unless-stopped`. Production usually `unless-stopped`. |
| `depends_on` (with `condition`) | `service_started`/`service_healthy`/`service_completed_successfully`. Healthchecks make `service_healthy` meaningful. |
| `healthcheck` | `test`, `interval`, `timeout`, `retries`, `start_period`. Required for `service_healthy` to work. |
| `deploy.resources.limits` | `cpus`, `memory`, `pids`. Without limits, one container can exhaust host. Compose-V2 honors these; V1 ignored them (Swarm-only). |
| `build` | `context` + `dockerfile` + `args` + `secrets` + `target`. Build-time secrets via `secrets:` are best — `args:` end up in image history. |
| `image` | **Pin to a version tag**, ideally with a digest (`nginx:1.27-alpine@sha256:abc...`). `:latest` makes builds non-reproducible and is the #1 source of "worked yesterday" incidents. |

## Variable interpolation (gotcha-heavy)
- `${VAR}` — substituted from `.env` (in same dir as the compose file) or shell environment, at COMPOSE-PARSE time.
- `${VAR:-default}` — default if VAR unset OR empty.
- `${VAR-default}` — default ONLY if VAR unset (empty preserved).
- `${VAR:?error msg}` — fail if VAR unset/empty.
- `$$` — literal `$` (escape).
- Variables inside `environment:` ARE interpolated. Variables inside `env_file`'d files are NOT (those are passed to the container literally).
- **Don't store secrets in `.env` files alongside compose.yaml** — they're commonly committed. Use top-level `secrets:` with file mounts and add the secret files to `.gitignore`/`.dockerignore`.

## Compose V1 vs V2 differences
- **V1 (`docker-compose`, Python, deprecated):** `version: "3.x"` in the file controlled feature set. `secrets:` top-level was a Swarm-only feature for non-Swarm V1.
- **V2 (`docker compose`, plugin, current):** ignores `version:`. Compose Specification feature set always available. `secrets:` works in non-Swarm. `depends_on.condition` works. `--profile` and `name:` are first-class.
- The validator below works for both; use V2 if available.

## Validator
```
docker compose -f <file> config --quiet         # parses + validates, no output on success
docker compose -f <file> config                 # parses + prints the resolved/merged config (useful for verifying interpolation)
docker compose -f <file> config --services      # lists services; quick sanity
```

`docker compose config` also EXPANDS `${VAR}` references using `.env`/shell — useful for catching interpolation errors before runtime.

## Gotchas
1. **`version: "3.8"`** is ignored on modern V2 and prints a deprecation warning. Removing it is safe.
2. **`env_file: .env` and the implicit interpolation `.env`** are the same file but used differently — the implicit one feeds `${VAR}` at compose-parse, the explicit one feeds env at container start. Same path, different mechanism.
3. **`ports: "8080:80"` binds 0.0.0.0**. Add `127.0.0.1:` prefix for loopback-only.
4. **YAML number coercion.** `"01"` parses as the string "01"; `01` parses as integer 1. Quote anything that should be a string.
5. **YAML booleans gotcha (Norway problem).** `country: NO` → false. Quote yes/no/on/off/true/false strings.
6. **Bind mount permissions.** Files written by container may be owned by root (or the container's user UID, which may differ from host). On macOS/Docker Desktop, mounts go through a VM and have different perf characteristics.
7. **`network_mode: host` + macOS/Windows:** doesn't work the same as Linux because Docker runs in a VM. Host networking is mostly meaningful on Linux hosts.
8. **`restart: always`** restarts even after `docker compose down` if the container was created with that policy. `unless-stopped` is usually what you want.
9. **Multiple `-f` files merge ALL the way through arrays and maps** — but maps deep-merge and arrays REPLACE (not append). Override files often surprise here.

## After-edit checklist (FoFoConfig protocol)
1. Backup to `<file>.fofobak`.
2. Apply diff after operator confirms.
3. Run `docker compose -f <file> config --quiet`. Non-zero exit = invalid; restore from backup.
4. If `environment`/`env_file`/`secrets` was edited, verify the values aren't going to end up in `docker compose config` output (i.e. they're file-mounted secrets, not env interpolation).
5. If `ports` were added/changed, surface which interface they bind to (loopback vs 0.0.0.0) in the explanation.
6. **Suggest `docker compose up --force-recreate <service>` rather than `restart`** when env-file values changed; running containers don't pick up env changes via restart.
