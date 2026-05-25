---
name: systemd-unit
description: "systemd unit files (*.service, *.socket, *.timer, *.mount, *.target, *.path, *.slice). Use when the operator has a file in /etc/systemd/system/, /lib/systemd/system/, ~/.config/systemd/user/, or an INI-style file with [Unit]/[Service]/[Install] sections. Security-dense: ExecStart runs as root (system units) unless restricted; sandboxing options (Private*, Protect*, RestrictAddressFamilies, NoNewPrivileges) are the hardening surface."
version: 1.0.0
# systemd is Linux-only, but operators frequently admin Linux servers from macOS/WSL2 terminals.
# The skill is useful as a knowledge reference cross-platform even when the validator/paths only work on Linux.
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [config-format, systemd, linux, security-critical]
    related_skills: []
  fofoconfig:
    format: systemd_unit
    file_globs:
      - "/etc/systemd/system/*.service"
      - "/etc/systemd/system/*.socket"
      - "/etc/systemd/system/*.timer"
      - "/etc/systemd/system/*.mount"
      - "/etc/systemd/system/*.target"
      - "/etc/systemd/system/*.path"
      - "/etc/systemd/system/*.slice"
      - "/lib/systemd/system/*.service"
      - "/lib/systemd/system/*.socket"
      - "/lib/systemd/system/*.timer"
      - "~/.config/systemd/user/*.service"
      - "~/.config/systemd/user/*.timer"
    discovery_commands: ["systemctl list-unit-files", "systemctl status <name>"]
    validator: "systemd-analyze verify <file>"
    syntax_kind: ini-like
    secret_keys_caution:
      - Environment           # values in service env; visible to ps/proc
      - EnvironmentFile       # path to env file; readable check matters
      - PassEnvironment       # which host env vars to pass through
      - LoadCredential        # credential file references
---

# systemd unit files

## Format overview
INI-like, with `[Section]` headers and `Key=Value` lines. Keys are case-sensitive (`ExecStart`, not `execstart`). Comments are `#` or `;`. Continuation across lines with trailing `\`. Multiple `ExecStart=` lines are usually replaced (not appended) — prefix with `-` to ignore failures, with `@` to override argv[0], with `+` to run with elevated privileges.

Drop-ins: `/etc/systemd/system/<unit>.d/*.conf` extend/override settings without editing the original unit file. Preferred over editing system-installed units in `/lib/systemd/system/`.

## File locations & precedence
systemd searches (LATER wins for system units):
1. `/lib/systemd/system/` — distro-installed units. Don't edit; will be overwritten by package updates.
2. `/etc/systemd/system/` — admin-managed; takes precedence over /lib.
3. `/run/systemd/system/` — runtime; ephemeral, takes precedence over /etc.

Drop-ins applied last as overlays: `/etc/systemd/system/<unit>.d/*.conf`.

User units: `~/.config/systemd/user/` (runs as the operator, not root). Use `systemctl --user <action>`.

After editing: `systemctl daemon-reload` is REQUIRED for systemd to re-read the unit. Then restart with `systemctl restart <unit>`.

## Top-level structure (.service example)
```ini
[Unit]
Description=My API service
Documentation=https://example.com/docs/api
After=network-online.target postgresql.service
Wants=network-online.target
Requires=postgresql.service
ConditionPathExists=/etc/myapi/config.yaml

[Service]
Type=simple                                       # simple|exec|forking|oneshot|notify|notify-reload|dbus|idle
ExecStart=/usr/local/bin/myapi --config /etc/myapi/config.yaml
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=                                         # default is SIGTERM; usually OK

# Identity (drop root)
User=myapi
Group=myapi
DynamicUser=no                                    # if yes, no need for User=/Group=; system allocates ephemeral UID

# Environment
Environment="ENV=production" "LOG_LEVEL=info"
EnvironmentFile=-/etc/myapi/env                   # leading - = OK if missing
LoadCredential=db_password:/etc/myapi/secrets/db_password   # mounted at $CREDENTIALS_DIRECTORY/db_password

# Working directory and resources
WorkingDirectory=/var/lib/myapi
RuntimeDirectory=myapi                            # /run/myapi created with proper perms
StateDirectory=myapi                              # /var/lib/myapi
LogsDirectory=myapi                               # /var/log/myapi
ConfigurationDirectory=myapi                      # /etc/myapi (read-only when sandboxed)

# Restart policy
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=60
StartLimitBurst=3

# Sandboxing (the meat of unit-file security)
NoNewPrivileges=true
ProtectSystem=strict                              # /usr, /boot, /etc read-only; ReadWritePaths= for exceptions
ProtectHome=true                                  # /home, /root, /run/user invisible (or read-only with =read-only)
PrivateTmp=true                                   # private /tmp and /var/tmp
PrivateDevices=true                               # only /dev/{null,zero,full,random,urandom,tty}
ProtectKernelTunables=true                        # /proc/sys, /sys, etc. read-only
ProtectKernelModules=true                         # block module load/unload
ProtectKernelLogs=true                            # kmsg invisible
ProtectControlGroups=true                         # cgroup interface read-only
ProtectClock=true                                 # block clock changes
ProtectHostname=true                              # block hostname changes
ProtectProc=invisible                             # other procs invisible in /proc
ProcSubset=pid                                    # only PID-related /proc entries
RestrictNamespaces=true                           # no clone(CLONE_NEW*)
RestrictRealtime=true                             # no SCHED_FIFO/RR
RestrictSUIDSGID=true                             # block suid/sgid binaries
LockPersonality=true                              # personality(2) locked
MemoryDenyWriteExecute=true                       # no W^X violations (no JIT)
SystemCallArchitectures=native                    # block compat syscalls
SystemCallFilter=@system-service                  # seccomp filter; @system-service is a safe set
CapabilityBoundingSet=                            # empty = no capabilities at all
AmbientCapabilities=                              # empty (default)
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6  # block raw sockets etc.
UMask=0077                                        # default file mode

# Resource limits
LimitNOFILE=4096
LimitNPROC=64
MemoryHigh=512M
MemoryMax=1G
TasksMax=128

[Install]
WantedBy=multi-user.target                        # `systemctl enable` creates a symlink here
```

## Section reference

### `[Unit]`
| Key | Notes |
|---|---|
| `Description` | Human-readable. Shown by `systemctl status`. |
| `Documentation` | URI(s); `man:`, `https://`, `info:`. |
| `Requires` / `Wants` / `Requisite` | Dependencies. `Requires` is hard (fail if dep fails); `Wants` is soft. `Requisite` is hard but doesn't start the dep. |
| `After` / `Before` | Ordering only; doesn't imply Requires/Wants. Use both: `After=network.target Requires=network.target`. |
| `Conflicts` | If listed unit starts, this one stops. |
| `Condition*` | Skip activation if condition not met. `ConditionPathExists`, `ConditionHost`, `ConditionACPower`, etc. |
| `Assert*` | Like Condition but failed assertion is a failure (vs skip). |

### `[Service]`
| Key | Notes |
|---|---|
| `Type` | `simple` (default since v240; was `oneshot` for non-Exec services), `exec` (like simple but wait for exec), `forking` (PIDFile= required), `oneshot` (run once, RemainAfterExit=true to keep state), `notify` (use sd_notify), `notify-reload` (modern, separates start/reload). |
| `ExecStart` | Main command. ABSOLUTE PATH (or `+`-prefixed for elevated). Multiple lines only for Type=oneshot. |
| `ExecStartPre`/`ExecStartPost`/`ExecStop`/`ExecStopPost`/`ExecReload` | Lifecycle hooks. `-` prefix tolerates failures. |
| `User` / `Group` / `SupplementaryGroups` | Drop privileges. **Critical.** |
| `DynamicUser` | Auto-allocate ephemeral UID per invocation; pairs with sandboxing. Trivial security win for services that don't need a persistent identity. |
| `Restart` | `no`/`always`/`on-success`/`on-failure`/`on-abnormal`/`on-watchdog`/`on-abort`. |
| `RestartSec` | Delay between restarts. |
| `Environment` | `Environment="K1=v1" "K2=v2"`. **Visible to `ps -eww`, `/proc/<pid>/environ`.** Not for secrets. |
| `EnvironmentFile` | Path(s) to env files (`KEY=value` lines, `=` separator, NO shell parsing). `-` prefix = OK if absent. |
| `LoadCredential` / `SetCredential` / `LoadCredentialEncrypted` | systemd's secrets mechanism. Mounts the credential at `$CREDENTIALS_DIRECTORY/<name>`. Encrypted variant uses TPM/credstore. Way better than env for secrets. |
| `WorkingDirectory` | Default `/`. Often the service's data dir. |
| `RuntimeDirectory` / `StateDirectory` / `LogsDirectory` / `ConfigurationDirectory` / `CacheDirectory` | systemd creates these with the right ownership (`User`/`Group`) and modes. Per-unit subdir of `/run`, `/var/lib`, `/var/log`, `/etc`, `/var/cache`. |
| `StandardInput`/`StandardOutput`/`StandardError` | `journal` (default), `tty`, `null`, `inherit`, `socket`, `file:<path>`, `append:<path>`. |
| `TimeoutStartSec`/`TimeoutStopSec` | How long to wait. Default 90s (start), 90s (stop). |

### Sandboxing keys (a.k.a. "everything you actually need")
| Key | What it locks down |
|---|---|
| `NoNewPrivileges` | `prctl(PR_SET_NO_NEW_PRIVS, 1)`. Blocks setuid escalation, file capabilities. **Set true unless you know you need otherwise.** |
| `ProtectSystem` | `true` (/usr, /boot read-only) / `full` (+/etc) / `strict` (entire fs r/o except /dev, /proc, /sys; ReadWritePaths= for exceptions). |
| `ProtectHome` | `true` / `read-only` / `tmpfs`. |
| `PrivateTmp` | Private /tmp + /var/tmp. |
| `PrivateDevices` | /dev minus host devices. |
| `PrivateNetwork` | No network at all (useful for compute-only services). |
| `PrivateUsers` | User namespace; UID 0 inside maps to non-root outside. |
| `ProtectKernelTunables`/`ProtectKernelModules`/`ProtectKernelLogs`/`ProtectControlGroups`/`ProtectClock`/`ProtectHostname`/`ProtectProc`/`ProcSubset` | All read-only / invisible variants. |
| `RestrictNamespaces`/`RestrictRealtime`/`RestrictSUIDSGID`/`RestrictAddressFamilies` | Block specific syscall/feature classes. |
| `CapabilityBoundingSet` / `AmbientCapabilities` | Linux capabilities; empty = no caps. |
| `SystemCallFilter` / `SystemCallArchitectures` | seccomp. `@system-service` is a known-good preset; remove specific classes with `~@something`. |
| `MemoryDenyWriteExecute` | No W^X — blocks most JIT engines (some need exemption). |
| `LockPersonality` | Block personality(2). |
| `UMask` | Default umask. |
| `KeyringMode` | `private` (default) / `inherit` / `shared`. |

Generate a hardening starting point with `systemd-analyze security <unit>` — gives a score out of 10 and a checklist.

### `[Install]`
| Key | Notes |
|---|---|
| `WantedBy` | `systemctl enable` symlinks into `<target>.wants/`. `multi-user.target` for system services. `default.target` for user services. |
| `RequiredBy` | Like WantedBy but a hard requirement. Rare. |
| `Alias` | Alternate names. |
| `Also` | Other units to enable/disable together. |

## Validator
```
systemd-analyze verify <file>             # syntax + best-practice warnings (don't take all suggestions)
systemd-analyze security <unit>           # hardening score (run AFTER daemon-reload + enable)
systemctl cat <unit>                      # show resolved unit (base + drop-ins)
journalctl -u <unit> -n 100               # logs for last 100 messages
```

## Gotchas
1. **Edit drop-ins, not /lib/systemd/system/** units. `systemctl edit <unit>` opens a drop-in editor.
2. **`daemon-reload` is REQUIRED** after editing any unit file. systemd will warn you if you forget.
3. **`Environment=` vs `EnvironmentFile=`** — both end up as env vars in the service. Environment= values appear in `systemctl show <unit>` output; EnvironmentFile= values do too unless redacted. Don't put real secrets in either; use `LoadCredential` or `LoadCredentialEncrypted`.
4. **`ProtectHome=true` + `User=` of a system user** is fine (system users don't have home dirs). For services that legitimately need to read `/home/foo/bar`, list specific paths in `BindReadOnlyPaths=` and use `ProtectHome=tmpfs` or `=false`.
5. **`ProtectSystem=strict` + need to write to /var/lib/myservice** — use `StateDirectory=myservice` (auto-creates and `ReadWritePaths=` it) rather than weakening ProtectSystem.
6. **`MemoryDenyWriteExecute=true`** breaks many JIT-using runtimes (Node, .NET, modern JVMs). Test before enabling for those.
7. **`Type=simple`** is the default; service is considered "started" the moment ExecStart is forked. If your daemon takes time to initialize, downstream `After=this.service` dependencies start too early. Use `Type=notify` + sd_notify, or `Type=exec` (waits for execvp success).
8. **`User=root` is implicit if `User=` is absent.** Always set it explicitly for non-root services.
9. **`Restart=always` + a service that crashes immediately** = infinite restart storm. Use `StartLimitIntervalSec=` + `StartLimitBurst=` to cap.
10. **User units run when the user is logged in.** Enable lingering (`loginctl enable-linger <user>`) for user services that should run when no session is active.
11. **Capitalization matters.** `User=` (capital U). systemd-analyze will catch typos.
12. **The directives `Requires=` / `After=` / `Wants=` are LISTS within ONE line, space-separated.** Multiple lines append. Easy to misread.

## After-edit checklist (FoFoConfig protocol)
1. Backup to `<file>.fofobak`.
2. Apply diff after operator confirms.
3. Run `systemd-analyze verify <file>` — non-zero / warnings reported.
4. **Do not run `daemon-reload` or `restart` yourself** — state-changing and out of scope. Surface the next commands to the operator: `sudo systemctl daemon-reload && sudo systemctl restart <unit>`.
5. Suggest `systemd-analyze security <unit>` after they restart — gives a hardening score (lower = better).
6. If `ExecStart=`, `User=`, or any sandboxing key was changed, suggest the operator check logs immediately after restart: `journalctl -u <unit> -n 50 -f`.
