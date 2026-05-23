# FoFoConfig — Requirements & Specification

**Product:** FoFoConfig
**Owner:** Sweet Papa Technologies LLC (FoFo)
**Version:** v0.1 (draft) · **Date:** 2026-05-23
**Status:** Spec locked for MVP build · target build window: 1 day
**Context:** Submission candidate for the Gemma 4 Challenge — "Build with Gemma 4" track

---

## 1. Summary

FoFoConfig is a **local, privacy-first config-file specialist agent**. You point it at a configuration file — or just name the program ("edit my nginx config") — and it identifies the format, explains it, and makes precise edits with a diff-and-confirm gate. If it meets a format it doesn't know, it researches the format on the web, distills the *structure* into a reusable knowledge card, and caches it so it never has to relearn.

Because inference is fully local (Gemma 4 E4B on-device), **it is safe to expose real secrets to it** — connection strings, keys, tokens — without anything leaving the machine. That single property is the entire reason the product exists.

**One-liner:** *The config tool you can paste your secrets into.*

FoFoConfig is not a new agent. It is a **thin, locked-down layer on top of HermesAgent** (Nous Research), pointed at a local Gemma 4 endpoint, with a tailored persona, a narrow toolset, a seeded skill pack, and an installer.

---

## 2. Design Principles (load-bearing)

1. **Local is the whole point.** The privacy promise is coupled to local inference. The moment any config content goes to a cloud API, the product loses its reason to exist. No cloud fallback for the model — ever.
2. **Structure, not values.** Learned knowledge (skills/memory) captures config *schema, keys, syntax, and gotchas* — never the user's actual secret values. This is the strongest secret-leak mitigation because it isn't pattern-matching; it's a hard content rule enforced by the persona.
3. **Public knowledge from the web; private data stays local.** Web search only ever touches general format documentation ("what is an nginx upstream block"). The user's file contents never enter a query.
4. **Design for the small model.** E4B is reliable when the task is narrow: few tools, clear schemas, deterministic scaffolding, sequential (not parallel) tool calls, and a human confirm gate. We do not ask E4B to free-roam.
5. **Reuse Hermes; don't rebuild.** Memory, the skill-accretion loop, file editing, checkpoints, the confirm gate, secret redaction, and the TUI all already exist. FoFoConfig is configuration + persona + skills + installer.
6. **Redaction is defense-in-depth, not containment.** Per Hermes's own security posture, pattern redaction reduces casual leakage but is not a hard boundary. The guarantees are: (a) local inference, (b) structure-not-values, (c) redaction as a third layer.
7. **The build is research-driven.** The AI coding agent implementing FoFoConfig **must do ad-hoc web research as it goes** — confirming exact Hermes config key names, current tool/skill/CLI APIs, the OpenAI-compatible endpoint config shape, and platform-specific paths — rather than relying on memory. Hermes and Gemma 4 are fast-moving; SOUL.md, the seed skills, the installer, and config wiring must be written against *freshly verified* docs, not assumptions. Treat "look it up before wiring it" as a hard build rule.

---

## 3. Architecture & Components

```
┌─────────────────────────────────────────────────────────────┐
│  fofoconfig launcher (thin shell wrapper)                     │
│    sets HERMES_HOME=~/.fofoconfig  →  launches Hermes TUI      │
│    optional subcommands: fofoconfig edit nginx | explain <f>  │
└───────────────────────────────┬───────────────────────────────┘
                                │
┌───────────────────────────────▼───────────────────────────────┐
│  HermesAgent (isolated profile @ ~/.fofoconfig)                │
│   • TUI: streamable tool output, history, autocomplete         │
│   • Persona: SOUL.md (config specialist)                       │
│   • Tools (whitelisted): read_file, write_file/edit,           │
│       terminal(allowlisted), web_search, web_extract,          │
│       skill_manage, memory                                     │
│   • Safety: redact_secrets ON · command_allowlist · Tirith     │
│       scan · dangerous-command approval · Checkpoints/rollback │
│   • Knowledge: skills/ (format-cards) · memories/              │
└───────────────────────────────┬───────────────────────────────┘
                                │ OpenAI-compatible HTTP (localhost:11434/v1)
┌───────────────────────────────▼───────────────────────────────┐
│  Ollama 0.22+ (auto-MLX on Apple Silicon)                      │
│   model: gemma4:e4b  · Q8 · thinking OFF · num_ctx set         │
│   native function calling · native multimodal (image)          │
└─────────────────────────────────────────────────────────────┘
```

**Component responsibilities**

| Layer | Choice | Why |
|---|---|---|
| Inference | Ollama 0.22+ serving `gemma4:e4b` (Q8) | Auto-uses MLX on Apple Silicon; OpenAI-compatible endpoint; fully scriptable for installer; tool-call fixes landed in 0.22 |
| Agent | HermesAgent (isolated HERMES_HOME) | Provides memory, skills, file editing, checkpoints, confirm gate, redaction, TUI |
| Lockdown | tool whitelist + command_allowlist + redact_secrets | Narrow attack surface; small-model-friendly; secret hygiene |
| Knowledge | Hermes Skills (agentskills.io standard) | The format-card accretion loop *is* Hermes Skills |
| Persona | SOUL.md | Enforces structure-not-values, diff-and-confirm, scope discipline |
| UX | Hermes TUI via `fofoconfig` launcher | Free, polished terminal UX; GUI deferred to v2 |
| Distribution | GitHub repo + one-line installer + dev.to writeup + demo video | Mirrors Hermes install ethos; skills shareable via agentskills.io |

---

## 4. Functional Requirements

### F1 — Locate & understand a config (by file or by program name)
- **WHAT:** User supplies a path *or* names a program ("edit my nginx config"). FoFoConfig locates the file, reads it, identifies the format, and explains it (key-by-key on request).
- **HOW:** Allowlisted discovery (`which`, `nginx -t`, known config locations, `find`). The located path is **confirmed with the user before any read/edit**. Reading uses Hermes `read_file` (prefer file-reference over asking the user to paste, to keep secrets out of the chat transcript).

### F2 — Adaptive format learning (HERO feature)
- **WHAT:** On an unfamiliar format/tool, FoFoConfig researches it on the web, distills a **format-card**, caches it as a Skill, and recalls it on future encounters instead of re-researching.
- **HOW:** `web_search` (ddgs default) → `web_extract`/fetch the best doc → distill into a Skill via `skill_manage`. **Format-cards capture structure only** (syntax, keys, valid values, gotchas, validation command) — never user values. Subsequent runs hit the skill, not the web.

### F3 — Safe editing (diff + confirm)
- **WHAT:** Every change is proposed as a diff, confirmed by the user, then applied.
- **HOW:** Hermes built-in file editing (NOT OpenCode — see §10). Mutating actions route through Hermes's dangerous-command approval gate (fail-closed on timeout). Combined with §F6 backup + Hermes Checkpoints/`/rollback`.

### F4 — Persistent skill library (accretion)
- **WHAT:** A growing local knowledge base of formats FoFoConfig has learned; it gets faster and smarter over repeated use.
- **HOW:** Hermes Skills in `~/.fofoconfig/skills/`, agentskills.io-compatible (shareable). Demo seed: 1–2 hand-written format-cards so recall demonstrates instantly.

### F5 — Locked-down execution
- **WHAT:** FoFoConfig can only do config work; no broad system access.
- **HOW:** `hermes tools` disables everything except the whitelist (§7). `security.command_allowlist` restricts shell to read/discovery/validate commands. Tirith scan + approval gate active. Optional Docker backend for hard isolation (§6.4).

### F6 — Backup before edit (REQUIRED)
- **WHAT:** Always back up a file immediately before editing it. Keep exactly **one** backup at a time.
- **HOW:** Two layers. (1) Hermes Checkpoints auto-snapshot the working directory before file changes (`/rollback` to undo). (2) FoFoConfig convention: write a single `<file>.fofobak` immediately before each edit, overwritten each time, giving a visible one-file restore point.
- **F6-stretch (post-edit validation):** if a validator exists for the format (`nginx -t`, `yamllint`, `jq`, JSON parse), run it after the edit and report. **Deferred** — only if MVP lands early.

### F7 — Multimodal intake (REQUIRED)
- **WHAT:** Accept a **screenshot** of a config or an error and reason over it (Gemma 4 E4B is natively multimodal).
- **HOW:** Image passed through Hermes → Ollama vision endpoint. **NOT yet de-risked** — this is a 3-link chain (TUI → Hermes tool loop → Ollama vision). See §9 step-zero smoke test. If the chain is flaky day-of, demote F7 to "best effort" and lead the demo with text intake.

---

## 5. Secret Hygiene & Logging Requirements

### SH1 — Secrets scrubber (REQUIRED, NEW)
- **WHAT:** Secrets must not persist in logs, history, memory, or skills. Any secret appearing in logs must be ephemeral (redacted).
- **HOW:**
  - Set `security.redact_secrets: true` (off by default). Enables Hermes's regex redactor + `RedactingFormatter`, masking API keys, token/secret env assignments, JSON secret fields, Authorization headers, private-key blocks, and DB connection-string passwords across all log output and before content enters conversation context.
  - **Verify the file-tool redaction fix is present** in the installed Hermes version (historical gap: `read_file` output exposed secrets while terminal output was masked). This is critical because reading config files is our primary path. Step-zero smoke test confirms it.
  - **Expand patterns** for config-heavy secrets: JWTs, AWS AKIA keys, Stripe keys, high-entropy strings, generic `KEY=`/`PASSWORD=`/`SECRET=` assignments.
  - **Structure-not-values rule** (persona-enforced): the dominant mitigation. Skills and memory never store secret values.
  - **Scrub-before-persist:** redaction runs before anything is written to `sessions/`, `memories/`, or logs — this is what lets persistent history coexist with ephemeral secrets.

### SH2 — Honest limitation (document, don't hide)
Pattern redaction is best-effort, not containment. The real guarantees are local inference + structure-not-values. Redaction is the third layer. State this plainly in the README so users calibrate trust correctly.

### SH3 — Persistent chat history (REQUIRED, NEW — but free)
- **WHAT:** Keep persistent chat history, reachable from the TUI. Build nothing major.
- **HOW:** Hermes already persists sessions (`~/.fofoconfig/sessions/`) and memory (`memories/`); the TUI exposes history, autocomplete, and session commands (`/resume`, `/new`, `/status`). Ensure the launcher and docs surface how to reach prior sessions. Redaction (SH1) guarantees that what persists is scrubbed.

---

## 6. Platform & Runtime Specs

### S1 — Runtime: Ollama (auto-MLX). NOT LiteRT.
- **Decision:** Ollama 0.22+ serving `gemma4:e4b` at Q8.
- LiteRT-LM is the **wrong tool here** — it's a mobile/edge embedding runtime with no OpenAI-compatible HTTP server, which Hermes requires. (LiteRT remains correct for the separate Android PAL/ORCA project.)
- On Apple Silicon, Ollama v0.19+ **automatically uses Apple's MLX framework** — no extra config needed; MLX-tagged builds (`gemma4:e4b-mlx-bf16`, ~10GB) are available if we want the explicit BF16 MLX path.
- A dedicated `mlx-lm`/`mlx_vlm` server is ~10–30% faster but more setup (uv + mlx-lm, Metal kernel compile on first run). **Deferred** — documented as a speed upgrade for v2.

**Required model/runtime settings**
| Setting | Value | Reason |
|---|---|---|
| Model | `gemma4:e4b` (official tag) | Edge variant; intentional small-model selection; multimodal; 128K context |
| Quantization | Q8 | Tool-call reliability (Q4 shows higher format-error rates) |
| Thinking/reasoning | **OFF** | Reasoning mode breaks expected tool-call formatting |
| `num_ctx` | 32768 default (expand to 131072 for large configs) | Ollama defaults to 4K silently; 24GB can handle 128K but be a good citizen on a busy Mac |
| Tool-call streaming | Non-streaming preferred | Streaming tool_calls had recognition bugs in some stacks |
| `OLLAMA_KEEP_ALIVE` | Default (~5 min idle unload) | Frees unified memory when idle — good for a busy M4; reload latency is acceptable |

**Target rig:** MacBook Pro M4, 24GB unified memory. E4B Q8 ≈ 4–5GB resident — sips memory, leaves headroom for normal work.

### S2 — UX: Terminal/TUI for MVP
- Ship via Hermes's TUI; do **not** build a custom renderer.
- A `fofoconfig` launcher sets `HERMES_HOME` and drops into the TUI. Optional convenience subcommands pre-seed the opening prompt.
- GUI (Ctrl+Space overlay, à la the existing chat-bar) is **v2**.

### S3 — Isolation: dedicated HERMES_HOME
- FoFoConfig runs in `HERMES_HOME=~/.fofoconfig`, fully separate from any existing `~/.hermes`. Config, memory, skills, sessions, credentials, and logs are sandboxed to that directory. Coexists with the operator's personal Hermes with zero interference. (Important: the operator already runs Hermes.)

### S4 — Terminal backend
- **Default:** `local` (the tool legitimately needs filesystem access to edit configs). Note: local backend runs as the user account with no fs isolation.
- **Hardening option:** `docker` backend (all caps dropped, no priv-esc, PID limits) with the target directory bind-mounted. Documented as the isolation upgrade for cautious users.

### S5 — Cross-platform support (REQUIRED: macOS, Linux, Windows)
- **WHAT:** FoFoConfig must run on macOS, Linux, and Windows. Cross-platform is a hard product requirement, not a future nicety.
- **HOW / reality check:**
  - **Ollama** is natively cross-platform (macOS/Linux/Windows), so the inference layer ports cleanly. MLX acceleration is **Apple-only**; on Linux/Windows with NVIDIA the path is CUDA, otherwise CPU (E4B is small enough for CPU fallback, slower).
  - **Hermes** supports Linux, macOS, and **Windows via WSL2** (not native Win32). So "Windows support" = WSL2 in practice; the installer must detect Windows and route through WSL2.
  - **F1 discovery is OS-aware:** config locations differ by platform (e.g., nginx, shell rc files, service configs). The locate logic and validators must branch per OS.
  - **Installer:** ship platform branches — a POSIX `install.sh` (macOS + Linux), and a Windows entry that bootstraps WSL2 then runs the same script inside it. Paths (`HERMES_HOME`) stay unix-style under WSL2.
- **Scope/sequencing (honest):** macOS Apple Silicon is the **reference implementation, verified day-one** (it's the demo rig). Linux and Windows/WSL2 are **required** and the installer is authored cross-platform-aware from the start, but full verification on those platforms follows the contest demo. The writeup should claim what's verified vs. authored-but-unverified accurately.

---

## 7. Hermes Configuration (concrete)

> Exact key names to be confirmed against `hermes config` on the installed version; intent is fixed.

**Inference (OpenAI-compatible → local Ollama)**
- Provider: OpenAI-compatible endpoint
- Base URL: `http://localhost:11434/v1`
- Model: `gemma4:e4b`
- API key: placeholder (e.g. `ollama`) — some clients require a non-empty key even though Ollama ignores it

**Tool whitelist (via `hermes tools` — disable all others)**
- `read_file`
- `write_file` / file edit
- `terminal` (constrained by command_allowlist)
- `web_search`, `web_extract`
- `skill_manage` (read + write skills)
- `memory`
- **Disabled:** browser automation, messaging gateways (Telegram/Discord/Slack/WhatsApp), delegation/subagents, cron, code execution beyond allowlist, MCP servers not needed

**`config.yaml` (key settings)**
```yaml
security:
  redact_secrets: true          # SH1 — ephemeral secrets in logs/context
  tirith_enabled: true          # keep the command scanner on
  command_allowlist:            # F5 — read/discovery/validate only
    - ls
    - cat
    - head
    - tail
    - find
    - which
    - grep
    - stat
    - nginx -t
    - yamllint
    - jq
    - "python -m json.tool"
web:
  backend: ddgs                 # F2 — keyless, zero-setup; SearXNG = opt-in
terminal:
  backend: local                # S4 — docker for hardening
```

**Environment / launcher**
- `HERMES_HOME=~/.fofoconfig` (S3)
- `HERMES_REDACT_SECRETS=true` (redundant safety with config)

**Custom Ollama Modelfile (optional, to pin runtime params)**
```
FROM gemma4:e4b
PARAMETER num_ctx 32768
PARAMETER temperature 0.2
# thinking/reasoning disabled per model/request config
```

---

## 8. Installer Flow (`install.sh`)

One-line installer, idempotent, platform-aware (S5). macOS Apple Silicon is verified day-one; Linux and Windows/WSL2 branches authored from the start.

1. **Preflight** — detect OS/arch. On macOS confirm Apple Silicon. On Windows, detect and bootstrap WSL2, then continue inside it. On Linux, detect NVIDIA/CUDA vs CPU. Check available memory (≥16GB recommended; ≥24GB ideal).
2. **Ollama** — check `ollama --version`; install/upgrade to 0.22+ if needed (`brew install ollama` or official installer). Optionally enable launch-at-login.
3. **Model** — `ollama pull gemma4:e4b`; optionally `ollama create fofoconfig-gemma4 -f Modelfile` to pin `num_ctx`/params.
4. **Hermes** — check for `hermes`; install via official one-liner if missing. **Verify version includes the file-tool redaction fix** (SH1).
5. **Isolated profile** — create `~/.fofoconfig`; run minimal `hermes setup` (no portal); write `config.yaml` (§7); apply tool whitelist via `hermes tools`.
6. **Persona & knowledge** — drop `SOUL.md` (§9), seed 1–2 format-card skills, scaffold `MEMORY.md`/`USER.md`.
7. **Launcher** — install `fofoconfig` script (sets `HERMES_HOME`, launches TUI; convenience subcommands).
8. **Step-zero smoke tests** — see §9. Fail loudly with remediation hints.

---

## 9. SOUL / Persona (outline) + Step-Zero Verification

**SOUL.md enforces:**
- Identity: a careful config-file specialist. Stays in scope; declines unrelated tasks.
- Always read the file in place (prefer file-reference over asking the user to paste).
- Identify the format. If unknown → research (web) → distill a **structure-only** format-card skill → cache. Never put secret values in skills, memory, or logs; refer to them as placeholders.
- Web is for *public format knowledge only* — never send file contents to the web.
- Before any edit: write the single `.fofobak` backup → present a diff → require explicit confirmation → apply.
- Validate after edit when a validator exists (F6-stretch).
- Sequential tool use; one clear action at a time.

**Step-zero smoke tests (run by installer, and first thing in the build):**
1. **Tool-calling fires** — define a trivial tool; confirm Gemma 4 E4B actually invokes it via the local endpoint (the single biggest technical risk). Fallback ladder if it fails: confirm Ollama ≥0.22, Q8 not Q4, official tag, thinking OFF, non-streaming; last resort llama.cpp `--jinja`.
2. **Multimodal flows (F7)** — pass a screenshot; confirm the image reaches the model and is described. If broken, demote F7 to best-effort.
3. **Redaction works (SH1)** — `read_file` on a fixture containing a fake API key + DB password; confirm both are masked in tool output AND in `~/.fofoconfig/logs/`.
4. **Endpoint reachable** — Hermes successfully calls `localhost:11434/v1`.

---

## 10. Out of Scope (today)

- **Finetuning** — no dataset ready; high-risk in a one-day window; well-scaffolded stock E4B is a stronger submission. Future: train on accumulated usage logs.
- **OpenCode delegation** — overkill for small targeted config edits; adds npm/brew install + its own auth + its own Gemma-4-via-Ollama tool-call brittleness; local-model boundary-drift risk (editing the wrong file) is the exact failure we must avoid. Hermes built-in editing + checkpoints + confirm gate is simpler and safer. (v2 note only.)
- **GUI overlay** — v2.
- **Multi-user RBAC** — Hermes gateway permission tiers are a proposed feature; irrelevant for single-operator local use.
- **Broad DevBuddy features** (disk cleanup, version management, vuln scanning) — different product; staying narrow is what makes this shippable and makes E4B reliable.
- **Audio intake** — E4B supports it, not needed here.

---

## 11. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| E4B tool-calling unreliable | Narrow toolset, Q8, thinking OFF, non-streaming, sequential calls; fallback to 26B MoE (runs fine on 24GB, ~4B active) |
| F7 multimodal chain breaks | Step-zero smoke test; demote to best-effort if flaky |
| File-tool redaction gap leaks secrets | Verify fix in installed Hermes version (step-zero) |
| Secrets in persistent history | `redact_secrets` scrubs before persist + structure-not-values + file-reference-over-paste |
| Redaction over-trusted as a boundary | README states plainly: defense-in-depth, not containment |
| Busy Mac memory pressure | E4B Q8 small footprint; keep-alive idle-unload; default num_ctx 32K |
| Agent edits wrong file | Confirm path (F1) + diff-and-confirm (F3) + `.fofobak` + Checkpoints |

---

## 12. Future (v2+)

- GUI: Ctrl+Space overlay chat bar.
- `mlx-lm`/`mlx_vlm` direct serving for 10–30% speed.
- SearXNG-via-Docker as a privacy-purist search option (search-only; pair with an extract backend).
- F6 post-edit validation expanded across formats.
- Publish curated format-cards to agentskills.io (community + acquisition angle).
- Encryption-at-rest for any cached config references.
- Native Windows (Win32) support without the WSL2 dependency.

---

## Appendix A — Sources consulted (2026)

- Gemma 4 model card / function calling — ai.google.dev/gemma
- Gemma 4 + Ollama setup, MLX on Apple Silicon, tool-call fixes (0.22) — codersera, mindwiredai, haimaker
- Gemma 4 + MLX direct serving — gemma4.dev, everyhub
- HermesAgent docs: configuration, security, web-search, features, skills — hermes-agent.nousresearch.com & github.com/NousResearch/hermes-agent
- Hermes secret redaction (`security.redact_secrets`, `agent/redact.py`, RedactingFormatter) — Hermes config docs & mudrii/hermes-agent-docs
- Hermes file-tool redaction gap — NousResearch/hermes-agent issues #363, #410
- Hermes OpenCode delegation skill — hermes-agent skills (autonomous-ai-agents/opencode)
- LM Studio MLX/OpenAI-compatible alternative — codersera, gemma4all

*This spec reflects information known as of 2026-05-23. Confirm exact Hermes config key names against the installed version during build.*
