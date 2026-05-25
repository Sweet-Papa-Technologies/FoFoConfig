---
name: ssh-client-config
description: "SSH client configuration files (~/.ssh/config, /etc/ssh/ssh_config, /etc/ssh/ssh_config.d/*). Use when the operator mentions SSH host config, asks about connection settings, ProxyJump, IdentityFile, ForwardAgent, or has a file with `Host`/`Match` blocks. NOT for sshd_config (server side) — that's a separate format. Security-dense: IdentityFile points at private keys; ForwardAgent forwards live auth; permissions on this file are policy-relevant."
version: 1.0.0
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [config-format, ssh, security-critical]
    related_skills: []
  fofoconfig:
    format: ssh_client_config
    file_globs:
      - "~/.ssh/config"
      - "~/.ssh/config.d/*"
      - "/etc/ssh/ssh_config"
      - "/etc/ssh/ssh_config.d/*"
    discovery_commands: ["ssh -G dummy 2>/dev/null | head", "ls -la ~/.ssh/"]
    validator: "ssh -F <file> -G dummy >/dev/null"
    syntax_kind: keyword-value
    secret_keys_caution:
      - IdentityFile
      - CertificateFile
      - PKCS11Provider
      - PasswordAuthentication  # informational; presence matters
      - ForwardAgent  # secret-adjacent: enables key forwarding
      - User  # not secret but PII
---

# SSH client configuration (`~/.ssh/config`)

## Format overview
Block-structured. Each `Host <pattern>` (or `Match` block) opens a scope; subsequent indented `Keyword value` lines apply until the next `Host`/`Match`. First-match-wins per-keyword (later occurrences are IGNORED). Comments are `#`. Empty lines OK.

## File locations & permissions
- **Per-user:** `~/.ssh/config` — should be `600` (rw-------); ssh refuses to read group/world-readable files.
- **Include dir:** `~/.ssh/config.d/*` — included via `Include ~/.ssh/config.d/*` directive (operator must add it; not auto-loaded by openssh < 7.3).
- **System-wide:** `/etc/ssh/ssh_config`, `/etc/ssh/ssh_config.d/*` — defaults; per-user overrides win.
- **Directory perms:** `~/.ssh/` should be `700`. ssh-keygen and ssh both warn loudly otherwise.

## Top-level structure
```
# Per-host alias with bastion hop
Host bastion
  HostName bastion.example.com
  User admin
  IdentityFile ~/.ssh/bastion_ed25519       # [SECRET-ADJACENT: points at private key]
  IdentitiesOnly yes

Host prod-*
  ProxyJump bastion
  User deploy
  IdentityFile ~/.ssh/prod_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking yes

# Defaults — keep this LAST (first-match-wins)
Host *
  AddKeysToAgent yes
  ServerAliveInterval 60
  HashKnownHosts yes
```

## Common directives

| Directive | Type | Notes |
|---|---|---|
| `HostName` | hostname/IP | The real target. `Host` is the alias; `HostName` is what ssh actually connects to. |
| `User` | username | If absent, uses local username. |
| `Port` | int | Default 22. |
| `IdentityFile` | path | Private key. Multiple allowed — ssh tries each in order. **Pair with `IdentitiesOnly yes` or ssh-agent may offer ALL loaded keys to the server, leaking key fingerprints.** |
| `IdentitiesOnly` | yes/no | Force ssh to use ONLY the listed `IdentityFile`s. Strongly recommended whenever you set IdentityFile. |
| `ProxyJump` | host[,host...] | Modern bastion-hop syntax (replaces `ProxyCommand ssh -W`). Comma-separated for multi-hop. |
| `ProxyCommand` | command | Arbitrary command whose stdio is the SSH transport. **Security: this runs locally with your user's privileges and credentials available.** |
| `ForwardAgent` | yes/no | **DANGEROUS DEFAULT.** When yes, the remote host can use your ssh-agent to authenticate to other hosts. A compromised remote host can use any key loaded into your agent. **Default to `no` for everything except trusted bastions.** |
| `ForwardX11` | yes/no | Forwards X11 display. Untrusted X11 forwarding (`ForwardX11Trusted no`) is safer but rarely-tested. |
| `StrictHostKeyChecking` | yes/accept-new/no/ask | Controls whether ssh adds host keys to `known_hosts` automatically and what happens on mismatch. `no` accepts any key without verification — disables host authentication. `accept-new` is the modern default (auto-add unknown, refuse changed). |
| `HostKeyAlgorithms` | csv | Restrict to modern algorithms (`ssh-ed25519,rsa-sha2-512,rsa-sha2-256`). Old `ssh-rsa` (SHA-1) is deprecated. |
| `Ciphers` | csv | Modern: `chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr`. Avoid CBC modes and legacy stream ciphers. |
| `MACs` | csv | Modern: `umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com`. |
| `KexAlgorithms` | csv | Modern: `curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512`. |
| `UserKnownHostsFile` | path | Default `~/.ssh/known_hosts`. Use `/dev/null` only for ephemeral hosts (acceptable for short-lived CI containers). |
| `HashKnownHosts` | yes/no | Hash hostnames in `known_hosts` so leaks don't reveal what you connect to. Default no; recommend yes. |
| `ControlMaster`/`ControlPath`/`ControlPersist` | — | Connection multiplexing. Big speed win for repeated short sessions to same host. `ControlPath` should be in a directory only you can write (e.g. `~/.ssh/cm/%C`); `%C` hashes user/host/port/user for collision-free names. |
| `AddKeysToAgent` | yes/no/confirm/<time> | Auto-add identity to ssh-agent on first use. `confirm` prompts on each use. |
| `Include` | glob | Pull in other files. Useful for per-environment config split. Files included MUST also have safe perms. |

## Gotchas
1. **First-match wins, per-keyword.** A `Host *` block with `User root` BEFORE a more specific `Host github.com` with `User git` will set User to `root` for github.com. Always put `Host *` defaults LAST.
2. **`ForwardAgent yes` is footgun.** Operator's ssh-agent becomes usable by the remote host. Use `ssh -A` per-invocation if you need it, or restrict to a single trusted bastion.
3. **`StrictHostKeyChecking no`** disables host authentication. Operator's keystrokes can be MITM'd. Acceptable only for ephemeral / throwaway hosts that you accept zero trust to.
4. **Permissions matter.** `~/.ssh/` must be `700`, `~/.ssh/config` `600`, private keys `600`. SSH refuses to use looser permissions on private keys and warns loudly on the config file.
5. **`Include` path globs** are NOT recursive (no `**`). Use explicit `Include ~/.ssh/conf.d/* ~/.ssh/work/*` rather than a fancy pattern.
6. **Multi-line values** are not supported. Each directive is one line.
7. **Quotes:** values containing spaces (filenames!) need double-quotes. `IdentityFile "~/my keys/id"`.
8. **`ProxyJump bastion` and `IdentityFile ~/x` together:** the IdentityFile applies to the FINAL hop, not bastion. To use different keys per hop, set them in the bastion's own `Host bastion` block.

## Validator
```
ssh -F /path/to/config -G hostname-or-alias >/dev/null   # parses config, prints resolved settings (or fails on error)
ssh-keygen -F hostname                                    # check if a host is in known_hosts
```
Exit 0 = parses cleanly. Non-zero = syntax error; ssh prints line and reason.

## After-edit checklist (FoFoConfig protocol)
1. Backup to `<file>.fofobak`.
2. Apply diff after operator confirms.
3. Run `ssh -F <file> -G <alias> >/dev/null` for at least one alias to verify the file parses.
4. If `Host *` block was edited, suggest the operator try one specific known-good host as a smoke test.
5. **Do not edit private keys themselves** — those are `~/.ssh/id_*` files, a different format (PEM/OpenSSH key), and out of scope for config-file editing.
