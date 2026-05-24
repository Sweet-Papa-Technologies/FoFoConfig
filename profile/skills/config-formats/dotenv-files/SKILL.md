---
name: dotenv-files
description: ".env files and variants (.env.local, .env.production, .env.example). Use when the operator references an environment-variable config file or you see a file whose contents are `KEY=value` lines (one per line, no quoting required, optional `export` prefix). These files are SECRET-DENSE — every value should be treated as potentially sensitive."
version: 1.0.0
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [config-format, dotenv, env, secrets]
    related_skills: []
  fofoconfig:
    format: dotenv
    file_globs:
      - "**/.env"
      - "**/.env.*"
      - "!**/.env.example"
      - "!**/.env.sample"
    discovery_commands: ["find . -maxdepth 3 -name '.env*' -not -path '*/node_modules/*'"]
    validator: null
    syntax_kind: ini-like
    secret_keys_caution:
      - "*_KEY"
      - "*_SECRET"
      - "*_TOKEN"
      - "*_PASSWORD"
      - "*_PASS"
      - DATABASE_URL
      - DB_URL
      - REDIS_URL
      - AWS_SECRET_ACCESS_KEY
      - STRIPE_SECRET_KEY
      - JWT_SECRET
      - SENTRY_DSN
      - "*_API_KEY"
---

# .env files

## Format overview
A `.env` file is a flat list of `KEY=VALUE` assignments, one per line. There is no formal spec — behaviour varies by loader (Node `dotenv`, Python `python-dotenv`, Go `godotenv`, Docker Compose, Ruby `dotenv-rails`). Treat **every value as a potential secret** unless the file is `.env.example` / `.env.sample` (templates with placeholder values).

## File locations
- **Project root.** `.env`, `.env.local`, `.env.development`, `.env.production`, `.env.test`.
- **Per-service.** Some monorepos have `apps/<svc>/.env`.
- **System-wide.** Not standard; `.env` is per-project.

## Syntax
```
# Comments start with '#'
KEY=value
KEY_WITH_QUOTES="value with spaces"
KEY_WITH_SINGLE='no $VAR interpolation here'
EXPORTED_KEY=value           # optional `export ` prefix accepted by most loaders
MULTILINE_KEY="line one\nline two"   # double-quoted strings support \n
EMPTY_KEY=
INHERITED_KEY=${OTHER_KEY}    # variable expansion — varies by loader
```

## Loader differences (gotchas)
1. **Quoting.** Node `dotenv` and Python `python-dotenv` both *strip* surrounding quotes. Bash `source .env` does not — quotes become part of the value.
2. **Variable expansion (`${VAR}`).** Supported by `python-dotenv` (opt-in), Node `dotenv-expand`, Docker Compose. NOT supported by base `dotenv` (Node).
3. **Comments at end of line.** `KEY=value # comment` — some loaders treat ` # comment` as part of the value unless the value is quoted. Always quote values that contain `#`.
4. **Whitespace.** Leading/trailing whitespace around `=` is loader-dependent. Most strip; some don't.
5. **Multiline values.** Only double-quoted strings, only `\n`/`\t` escapes, only some loaders.
6. **Boolean values.** `true`/`false` are *strings* — never `bool`. Likewise numbers.
7. **Precedence.** Most apps load `.env`, then `.env.<environment>`, then `.env.local`, with later files overriding earlier. `.env.local` is normally git-ignored.

## Common keys (with masking guidance)
| Key pattern | Typical contents | FoFoConfig handling |
|---|---|---|
| `DATABASE_URL` / `DB_URL` | `postgres://user:PASS@host:5432/db` | The password segment is a secret. Hermes redactor catches this. |
| `*_API_KEY`, `*_SECRET`, `*_TOKEN`, `*_PASSWORD` | high-entropy strings | Mask in any diff explanation; preserve verbatim in the file. |
| `STRIPE_SECRET_KEY` | `sk_live_…` / `sk_test_…` | Redactor pattern matches. |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | `AKIA…` (id) + 40-char secret | Pair — both are sensitive together. |
| `JWT_SECRET` | random string | Rotating this invalidates all issued tokens — warn the operator before editing. |
| `SENTRY_DSN` | `https://<pub>:<priv>@…` | DSN contains a public+private key pair. |
| `NODE_ENV` / `RAILS_ENV` / `APP_ENV` | `development`/`production`/`test` | Not secret; safe to discuss freely. |
| `PORT`, `HOST`, `LOG_LEVEL` | numbers / hostnames | Not secret. |

## Editing protocol (FoFoConfig)
1. **Backup first** to `<file>.fofobak`.
2. **Never echo values in chat.** When proposing a diff that changes `DATABASE_URL`, show the diff with the value masked in the *explanation* ("DATABASE_URL changing from `<existing>` to `<new>`"), but the diff itself must contain the literal new value the operator gave.
3. **Refuse to invent values.** If the operator asks "set my STRIPE_SECRET_KEY to a test key," ask them for the literal value — do not fabricate one.
4. **Suggest `.env.example` updates** when adding a new key. New keys in `.env` should also appear in `.env.example` with a placeholder.

## Validator
There is no canonical validator. Sanity-check by:
- Counting lines: `grep -c '^[A-Z_][A-Z0-9_]*=' <file>` — should match expected.
- Detecting accidental duplicates: `grep -oE '^[A-Z_][A-Z0-9_]*' <file> | sort | uniq -d` — should be empty.

## When NOT to use this skill
- The file is `.env.example` or `.env.sample`: it's a template, edit freely.
- The file is named `.env` but the contents are YAML/JSON: it's mis-named — identify the real format first.
