---
name: git-config
description: "Git configuration files (~/.gitconfig, ~/.config/git/config, /etc/gitconfig, per-repo .git/config). Use when the operator mentions git aliases, user identity, credential helpers, GPG/SSH signing, URL rewrites, or has an INI-style file with [section] and [section \"subsection\"] headers. Security-relevant: credential.helper handles passwords; signing key paths point at secrets; insteadOf URL rewrites can silently route traffic."
version: 1.0.0
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [config-format, git, ini-like]
    related_skills: []
  fofoconfig:
    format: git_config
    file_globs:
      - "~/.gitconfig"
      - "~/.config/git/config"
      - "/etc/gitconfig"
      - ".git/config"
      - "**/.git/config"
    discovery_commands: ["git config --list --show-origin", "git config --global --list"]
    validator: "git config --file <path> --list >/dev/null"
    syntax_kind: ini-like
    secret_keys_caution:
      - credential.helper
      - user.signingkey
      - gpg.program
      - http.<url>.extraheader  # may contain Authorization
      - sendemail.smtppass
      - "github.token"
---

# Git configuration

## Format overview
INI-like: `[section]` headers, `key = value` lines. Subsections in quotes: `[remote "origin"]`. Multi-word section names are lowercase: `core`, `user`, `remote`, `branch`, `credential`. Boolean values are flexible — `true`/`yes`/`on`/`1` vs `false`/`no`/`off`/`0` all accepted.

## File locations & precedence
Git reads (in order; LATER WINS):
1. `/etc/gitconfig` (system-wide)
2. `~/.config/git/config` then `~/.gitconfig` (user-global; XDG path checked first)
3. `<repo>/.git/config` (repo-local)
4. Command-line flags / env vars (`GIT_CONFIG_GLOBAL` etc.)

Use `git config --list --show-origin` to see which file set each value.

## Top-level structure
```
[user]
  name = Operator Name
  email = operator@example.com
  signingkey = ABC1234567890DEF                  # GPG key id, or SSH key path with `gpg.format = ssh`

[core]
  editor = vim
  autocrlf = input
  excludesfile = ~/.config/git/ignore

[credential]
  helper = osxkeychain                           # macOS keychain; secrets-stored
  # helper = store                               # plaintext ~/.git-credentials — avoid

[gpg]
  format = ssh                                   # since git 2.34; sign with SSH keys

[gpg "ssh"]
  allowedSignersFile = ~/.config/git/allowed_signers

[commit]
  gpgsign = true

[push]
  default = simple
  autoSetupRemote = true

[pull]
  rebase = true                                  # vs merge

[remote "origin"]
  url = git@github.com:org/repo.git
  fetch = +refs/heads/*:refs/remotes/origin/*

[url "git@github.com:"]
  insteadOf = https://github.com/                # rewrite https URLs to ssh — silently
```

## Common keys (with security notes)

| Key | Notes |
|---|---|
| `user.name` / `user.email` | PII. Visible in every commit. Per-repo override common (work vs personal). |
| `user.signingkey` | GPG key id, or SSH public-key path / public-key string. **Private key lives elsewhere** (`~/.gnupg/` or `~/.ssh/id_*`) — git only references it. |
| `commit.gpgsign` / `tag.gpgsign` | Sign commits/tags by default. With a hardware token (YubiKey), strong tamper-evidence. |
| `credential.helper` | How git stores HTTP(S) credentials. Good: `osxkeychain` (macOS Keychain), `wincred` (Windows Credential Manager), `libsecret` (Linux gnome-keyring), `gh auth git-credential` (gh CLI managed). **Bad: `store` (plaintext `~/.git-credentials`), `cache` (in-memory, OK for short sessions).** A custom helper is a script — read its source before approving. |
| `gpg.program` | Path to gpg binary. Could redirect to a wrapper. Treat with suspicion in repo-local config. |
| `http.<url>.extraheader` | Per-URL extra HTTP headers. **Can contain `Authorization: Bearer <token>`** — secret. |
| `http.proxy` / `https.proxy` | HTTP proxy URL. **Can include credentials in userinfo** (`http://user:pass@proxy/`). |
| `sendemail.smtppass` | SMTP password for `git send-email`. **PLAINTEXT secret if set here** — prefer `smtpencryption = tls` + helper. |
| `core.sshCommand` | Override ssh binary for git operations. Could point at a wrapper. Treat with suspicion in repo-local config. |
| `core.fsmonitor` | Path to fsmonitor binary that runs on every git operation. Repo-local fsmonitor in a cloned repo = arbitrary code execution. **Git ≥2.35.2 refuses repo-local `core.fsmonitor` for safety.** Verify on older git. |
| `safe.directory` | Git ≥2.35.2: paths git will trust ownership of (prevents the CVE-2022-24765 sudo trust issue). Add specific paths, not `*`. |
| `url.<base>.insteadOf` | Rewrites URL prefixes. **Repo-local `[url ...]` from an untrusted repo can silently redirect `git submodule add` etc. to attacker-controlled URLs.** Inspect any `[url ...]` in cloned repos. |
| `protocol.<name>.allow` | Controls which protocols `git submodule` accepts (`always`/`never`/`user`). Modern defaults disable `ext`, `ftp`, `ftps`. |
| `submodule.recurse` | Whether `git pull` auto-recurses into submodules. With safe per-protocol allow lists, OK; with looser config, surface for tricks. |
| `alias.<name>` | Aliases. **`!cmd` aliases run shell** — repo-local alias `!rm -rf /` is a thing. Inspect any `!`-prefixed alias in a cloned repo. |
| `push.default` | `simple` (modern, push current branch to matching upstream only) vs `matching` (push all matching branches — error-prone). |
| `pull.rebase` | `true`/`false`/`merges`/`interactive`. Affects merge graph. Operator preference. |
| `init.defaultBranch` | Default branch name for `git init`. `main` is common. |

## Gotchas
1. **Repo-local `core.fsmonitor`, aliases beginning with `!`, and `[url ...].insteadOf`** can be active-code-execution vectors in cloned repos. Modern git (≥2.35.2) disables some of this automatically; older git is exposed.
2. **`safe.directory`** matters when working on shared filesystems (or after `chown`). `*` is a sledgehammer; prefer specific paths.
3. **`credential.helper = store`** writes plaintext credentials to `~/.git-credentials`. Suggest a keychain helper instead.
4. **GPG vs SSH signing.** Git 2.34+ supports `gpg.format = ssh` — simpler, no GPG keyring management. Requires `gpg.ssh.allowedSignersFile` to VERIFY signatures.
5. **`user.email` per-repo.** Common workflow: a per-repo `[user]` block to sign commits with different identities for personal vs work. Easy to forget; git ≥2.32 supports `[includeIf "gitdir:~/work/"]` to scope automatically.
6. **CRLF policy.** `core.autocrlf = true` (Windows) vs `input` (mac/linux) vs `false`. Mixed-team repos use `.gitattributes` instead.
7. **`core.hooksPath`** override means hooks in a non-standard location run instead of `.git/hooks/`. Cloned-repo hooks are NOT executed unless the user opts in (`git config --local core.hooksPath .githooks` is a common pattern).
8. **`fetch.fsckObjects` / `transfer.fsckObjects`** validate object integrity on receive — recommended `true` for defense against malicious pack files.

## Validator
```
git config --file <path> --list >/dev/null   # parses + lists; non-zero on syntax error
git config --file <path> --show-origin --list   # shows which file each value came from (use repo-wide --list --show-origin)
git config --list --show-origin --show-scope   # full provenance dump
```

## After-edit checklist (FoFoConfig protocol)
1. Backup to `<file>.fofobak`.
2. Apply diff after operator confirms.
3. Run `git config --file <file> --list >/dev/null` to verify parse.
4. If `credential.helper` changed, suggest the operator test with `git ls-remote <a-private-repo>` before relying on it.
5. **Refuse to add `[url ...].insteadOf`, `core.fsmonitor`, `core.hooksPath`, or `alias.<name>=!cmd` to a REPO-LOCAL config from a cloned repo without an explicit operator override** — these are RCE vectors. Operator confirmation should be specific ("I trust this insteadOf to redirect github → my mirror").
