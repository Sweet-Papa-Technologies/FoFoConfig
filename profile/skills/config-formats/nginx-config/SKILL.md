---
name: nginx-config
description: "Nginx HTTP server configuration files (nginx.conf, sites-available/*, conf.d/*.conf). Use when the operator mentions nginx, has a file matching nginx syntax (curly-brace blocks like `http { server { location / { ... } } }`), or asks to edit a web-server reverse-proxy / upstream / SSL config. Validator: `nginx -t`."
version: 1.0.0
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [config-format, nginx, web-server, reverse-proxy]
    related_skills: []
  fofoconfig:
    format: nginx
    file_globs:
      - "/etc/nginx/nginx.conf"
      - "/etc/nginx/sites-available/*"
      - "/etc/nginx/sites-enabled/*"
      - "/etc/nginx/conf.d/*.conf"
      - "/usr/local/etc/nginx/nginx.conf"
      - "/opt/homebrew/etc/nginx/nginx.conf"
    discovery_commands: ["which nginx", "nginx -V", "nginx -T"]
    validator: "nginx -t"
    syntax_kind: custom
    secret_keys_caution:
      - ssl_certificate_key
      - ssl_trusted_certificate
      - auth_basic_user_file
      - proxy_set_header
---

# nginx configuration

## Format overview
Nginx config is a declarative, hierarchical, curly-brace-block format. The top level is the **main context**; nested inside are **events**, **http**, **stream**, and **mail** contexts. Inside `http` are **server** blocks (virtual hosts), and inside `server` are **location** blocks (URL routes). Each directive is `name value;` (semicolon-terminated, NOT comma).

## File locations
- **Linux (Debian/Ubuntu):** `/etc/nginx/nginx.conf` includes `sites-enabled/*` and `conf.d/*.conf`.
- **Linux (RHEL/CentOS):** `/etc/nginx/nginx.conf` includes `conf.d/*.conf` (no sites-available pattern by default).
- **macOS (Homebrew):** `/opt/homebrew/etc/nginx/nginx.conf` (Apple Silicon) or `/usr/local/etc/nginx/nginx.conf` (Intel).
- **Windows:** not natively supported — operator likely uses WSL2 path or a container.

## Top-level structure
```
# main context
user nginx;
worker_processes auto;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;
  sendfile      on;
  keepalive_timeout  65;

  upstream <name> { server <host>:<port>; }

  server {
    listen 443 ssl http2;
    server_name <hostname>;
    ssl_certificate     <path>;
    ssl_certificate_key <path>;        # [SECRET-ADJACENT: file at path is the secret]
    location / {
      proxy_pass http://<upstream-name>;
      proxy_set_header Host $host;
    }
  }
}
```

## Common directives (by context)

| Directive | Context | Type | Notes |
|---|---|---|---|
| `listen` | server | `<port>` or `<port> ssl` or `[::]:<port>` | Required per server block. |
| `server_name` | server | space-separated hostnames | Wildcards: `*.example.com`. |
| `root` | server, location | path | Document root for static files. |
| `index` | http, server, location | space-separated filenames | Defaults to `index.html`. |
| `location` | server | `<modifier> <pattern>` | Modifiers: `=` exact, `~` regex, `~*` regex i, `^~` prefix-priority. |
| `proxy_pass` | location | URL | Trailing slash semantics matter — `proxy_pass http://x/` strips the matched prefix; `proxy_pass http://x` preserves it. |
| `upstream` | http | block | Defines a load-balanced backend pool. |
| `ssl_certificate` / `ssl_certificate_key` | server | path | The key path is secret-adjacent; the file itself is the secret. |
| `return` | server, location | `<code> [text|url]` | For redirects: `return 301 https://$host$request_uri;`. |
| `rewrite` | server, location | `<regex> <replacement> [flag]` | Flags: `last`, `break`, `redirect`, `permanent`. |
| `include` | any | glob | Reads other files. The reason `nginx -T` is useful — dumps the fully-resolved config. |
| `add_header` | http, server, location | name value | Beware: inheritance is **replacement, not merge** — child contexts override parent entirely if they declare any `add_header`. |
| `auth_basic_user_file` | server, location | path | Path to htpasswd file. The file contents are secrets. |

## Gotchas
1. **Semicolons.** Every directive ends with `;`. Forgetting one is the #1 syntax error and `nginx -t` will point at the *next* line, which is misleading.
2. **`add_header` inheritance is replacement, not merge.** If a location declares any `add_header`, it loses all parent headers.
3. **`proxy_pass` slash semantics.** `proxy_pass http://backend/` and `proxy_pass http://backend` behave differently when the location has a prefix.
4. **`server_name` order matters for collisions.** First match wins; the default server is the one with `default_server` on its `listen`, or the first server block on that port.
5. **`if` is evil.** Inside `location`, `if` has surprising semantics; prefer `try_files`, `return`, or a separate location.
6. **`reload` vs `restart`.** `nginx -s reload` re-reads config without dropping connections; `restart` drops connections. Always `nginx -t` first.

## Validator
```
nginx -t                          # validates the running config tree
nginx -t -c /path/to/nginx.conf   # validates an alternate file
```
Exit code `0` = valid; non-zero = invalid (stderr contains the line number).

## After-edit checklist (FoFoConfig protocol)
1. Backup to `<file>.fofobak` (preferably via the deterministic `backup` quick_command if configured, else via the `file` toolset).
2. Apply diff after operator confirms.
3. Run `nginx -t`. If non-zero, *immediately* restore from `.fofobak` and report the error verbatim. Do not attempt auto-fix without operator confirmation.
4. Suggest `sudo nginx -s reload` to the operator. **Do not run reload commands yourself** — they are state-changing and out of scope.
