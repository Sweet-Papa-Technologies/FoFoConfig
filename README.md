<!-- markdownlint-disable MD033 MD041 -->

<p align="center">
  <img src="docs/assets/banner.png" alt="FoFoConfig — the config tool you can paste your secrets into" width="720" />
</p>

<h1 align="center">FoFoConfig</h1>

<p align="center">
  <strong>🔐 The config tool you can paste your secrets into.</strong><br/>
  <em>A privacy-first config-file specialist agent — powered by Gemma 4, run against any OpenAI-compatible endpoint <strong>you</strong> control.</em>
</p>

<p align="center">
  <a href="#-quick-start">Quick Start</a> ·
  <a href="#-what-it-does">What It Does</a> ·
  <a href="#-security--privacy">Security</a> ·
  <a href="#-skills">Skills</a> ·
  <a href="#-architecture">Architecture</a> ·
  <a href="#-contributing">Contributing</a>
</p>

<p align="center">
  <a href="https://github.com/Sweet-Papa-Technologies/FoFoConfig/blob/main/LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" /></a>
  <a href="https://ai.google.dev/gemma"><img alt="Powered by Gemma 4" src="https://img.shields.io/badge/gemma-4-4285F4" /></a>
  <a href="https://hermes-agent.nousresearch.com/"><img alt="Built on HermesAgent" src="https://img.shields.io/badge/agent-Hermes-9b59b6" /></a>
  <a href="https://agentclientprotocol.com/"><img alt="ACP" src="https://img.shields.io/badge/protocol-ACP-2ecc71" /></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20WSL2-lightgrey" />
</p>

---

## 🚀 Quick Start

```sh
git clone https://github.com/Sweet-Papa-Technologies/FoFoConfig.git
cd FoFoConfig
./install.sh                        # installs Hermes + launcher (no model pull!)
fofoconfig                          # opens the agent
```

That's it. `install.sh` will walk you through pointing FoFoConfig at the LLM endpoint of your choice (local Ollama, LAN box, your own server — see [Endpoint setup](#-endpoint-setup) below).

<p align="center">
  <img src="docs/assets/demo.gif" alt="FoFoConfig in action: explaining a .env file, showing a diff, confirming an edit" width="800" />
</p>

---

## 💡 What It Does

You point FoFoConfig at a **configuration file** — or just name the program (`"edit my nginx config"`) — and it:

| | |
|---|---|
| 🔎 **Finds it** | Locates candidate files on disk, asks you which one, never edits without confirmation. |
| 📖 **Explains it** | Walks through key by key, flags which lines hold secrets, uses placeholders in chat. |
| 📝 **Edits it safely** | Backup → unified diff → `y/n` confirm → apply → validate. Every change, no exceptions. |
| 🧠 **Learns new formats** | Met a format it doesn't know? It researches the docs (general format terms only, never your file contents) and caches a structure-only skill card for next time. |
| 💾 **Backs up** | Single `<file>.fofobak` per file, written before any edit. Plus Hermes Checkpoints (`/rollback`). |
| 🖼️ **Reads screenshots** | Paste an image of a config or an error with `Alt+V` — it reasons over it (Gemma 4 is natively multimodal). |
| 🛡️ **Refuses cloud LLMs** | By default, `fofoconfig setup` won't let you point it at api.openai.com, api.anthropic.com, etc. — that would defeat the entire purpose. |

### Example session

```text
$ fofoconfig edit nginx
[fofo] Tip: ask me — "edit the configuration for: nginx"

You: edit the configuration for: nginx → enable gzip for text/json responses

▸ read: /opt/homebrew/etc/nginx/nginx.conf
▸ skill view (nginx-config)
▸ patch (replace): /opt/homebrew/etc/nginx/nginx.conf

⚠ Permission requested: Approve edit: /opt/homebrew/etc/nginx/nginx.conf

─── diff for /opt/homebrew/etc/nginx/nginx.conf ───
@@ -22,6 +22,11 @@
     keepalive_timeout  65;
+    gzip on;
+    gzip_types text/plain text/css application/json application/javascript;
+    gzip_min_length 256;

  1) Allow edit (allow_once)
  2) Deny (reject_once)
Approve? [y/N or 1-2]: y
[fofo] backup: /opt/homebrew/etc/nginx/nginx.conf.fofobak
✓ Wrote. Validated with `nginx -t`: ok.

You: /exit
```

---

## 📦 Installation

### Requirements

- **Agent host** (your laptop / dev box): macOS, Linux, or Windows + WSL2. `python3` + `pip` or `pipx`. ~50 MB.
- **Inference host** (separate or same machine — see [Endpoint setup](#-endpoint-setup)): any OpenAI-compatible HTTP server with a Gemma 4 model. Local Ollama is the easiest starting point.

### Install (two stages)

**Stage 1 — agent layer (~30 sec, no model download):**

```sh
git clone https://github.com/Sweet-Papa-Technologies/FoFoConfig.git
cd FoFoConfig
./install.sh
```

This installs Hermes (via `pipx` or `pip`), writes a profile to `~/.fofoconfig`, installs the `fofoconfig` launcher into your `PATH`, and runs the endpoint setup wizard. **It does not pull a model and does not install Ollama** — those choices are yours.

**Stage 2 — point it at your endpoint:**

```sh
fofoconfig setup
```

The wizard:

1. ✅ Detects local Ollama if installed; lists pulled Gemma 4 models as options.
2. 🔍 Prompts for `base_url`, `model`, `api_key` (with sensible defaults).
3. 🛡️ Refuses known cloud LLM hostnames (`--i-know-what-im-doing` to override).
4. 🧪 **Verifies the endpoint meets Hermes' actual requirements** before saving: reachable → model loads → tool calling fires → runtime context ≥ 64K → vision capability (for screenshot support).
5. ✏️ Writes the verified config to `~/.fofoconfig/config.yaml`.

Re-runnable anytime as `fofoconfig setup`. Sanity check anytime with `fofoconfig doctor`.

### One-liner install

```sh
curl -fsSL https://raw.githubusercontent.com/Sweet-Papa-Technologies/FoFoConfig/main/install.sh | sh
```

### Windows (WSL2)

```sh
wsl --install -d Ubuntu       # if you don't have WSL2
# in WSL2:
git clone https://github.com/Sweet-Papa-Technologies/FoFoConfig.git
cd FoFoConfig && ./install.sh
```

Native Win32 support is on the [v2 roadmap](docs/Requirements-Specs.md#12-future-v2).

---

## 🌐 Endpoint setup

FoFoConfig is **bring-your-own-endpoint** by design. You pick where inference runs — we just verify it works.

### Option A — Local Ollama (easiest on-ramp)

Install Ollama from [ollama.com/download](https://ollama.com/download), then:

```sh
ollama pull gemma4:e4b-it-q8_0    # 12 GB GGUF Q8 — recommended (full multimodal)
# OR lighter:
ollama pull gemma4:e4b            # 9.6 GB Q4_K_M (still multimodal)
fofoconfig setup
```

> ⚠️ **Heads-up on memory:** running a 12 GB model + the agent + your daily-driver workload on one machine can pressure unified memory hard. On a 24 GB MacBook running everyday apps, **a dedicated inference host (LAN box) is recommended**. Setup will warn you and offer paths.

### Option B — Remote llama.cpp / vLLM / LM Studio (recommended for 16-24 GB rigs)

Run inference on a beefier server on your LAN. Then:

```sh
fofoconfig setup \
  --endpoint http://192.168.1.151:11434/v1 \
  --model gemma4:e4b-it-q8_0 \
  --api-key whatever
```

Verified working: **Ollama** (local + remote), **llama.cpp HTTP server**, **vLLM**, **LM Studio**. Anything that speaks `POST /v1/chat/completions` with tool-call support.

### Hermes' 64K runtime context floor

Hermes refuses any model loaded with `<64K` runtime context. Most Ollama Gemma 4 tags default to 32K. Setup auto-writes `model.ollama_num_ctx: 65536` into your config so this Just Works without a derived Modelfile. If you want a custom Modelfile anyway, one is generated at `~/.fofoconfig/Modelfile.example`.

---

## 🛡️ Security & Privacy

The privacy promise is **layered defense, ranked by strength**:

1. **🔒 Operator-controlled inference.** Your endpoint, your machine, your LAN, your trust. We refuse known cloud LLM endpoints by default — there's no path where `api.openai.com` accidentally gets your secrets.
2. **🧱 Structure-not-values.** The agent's persona (`SOUL.md`) forbids writing secret values into any skill, memory, log, or web query. It records the *shape* of configs only.
3. **📂 File-reference over paste.** The agent reads files via `read_file` so secrets don't enter the chat transcript.
4. **🚫 Path-policy gate.** The ACP client refuses to read or write known secret-store paths (`~/.ssh/id_*`, `~/.aws/credentials`, `~/.kube/config`, `/etc/sudoers`, password stores, GPG keys…). Even a prompt-injected agent can't exfiltrate them.
5. **🎭 Secret redaction.** Hermes' regex redactor masks API keys, JWTs, DB-URL passwords, `Authorization: Bearer`, PEM blocks, env-var assignments — in tool output and in logs.
6. **🚦 Diff-and-confirm at the protocol layer.** Every file edit surfaces as an [ACP](https://agentclientprotocol.com/) `request_permission` callback — unified diff rendered, `.fofobak` backup written before approval, your explicit `y/n`. Enforced by the **client**, not as an agent promise.
7. **🧾 File contents are data, not instructions.** The persona explicitly refuses to act on directives embedded in file comments (defense against [prompt injection via config files](https://hermes-agent.nousresearch.com/docs/user-guide/security)).

### Honest limits (please read)

- **Redaction is pattern-matching, not containment.** It catches the obvious — novel secret formats (custom token schemes, proprietary key prefixes) will flow through. Treat layers 1–4 as the real boundary.
- **Hermes' secrets-management story is still maturing** ([NousResearch/hermes-agent#410](https://github.com/NousResearch/hermes-agent/issues/410)). Plaintext `~/.fofoconfig/.env` storage and full env passthrough to subprocesses remain — don't put secrets in those places.
- **The `--i-know-what-im-doing` override** to the cloud-LLM blocklist exists for legitimate self-hosted-via-cloud-fronted-hostname cases (corporate LiteLLM proxy etc.). Using it is logged to `MEMORY.md` so the agent itself knows. **Don't use it to enable an actual cloud LLM provider** — you've voluntarily broken the entire privacy guarantee at that point.
- **Hardening upgrade:** flip `terminal.backend: docker` in `~/.fofoconfig/config.yaml` to run shell commands inside an isolated container.

Full threat model and design rationale: [Requirements-Specs.md §5](docs/Requirements-Specs.md#5-secret-hygiene--logging-requirements) and [design.plan.md](docs/design.plan.md).

---

## 🛠️ Use

```sh
fofoconfig setup              Configure or re-configure your endpoint (interactive)
fofoconfig                    Start an interactive ACP session
fofoconfig edit nginx         Seed: "edit the configuration for: nginx" + interactive
fofoconfig explain ~/.bashrc  Seed: "explain this config file: ~/.bashrc" + interactive
fofoconfig resume             Resume the most recent session
fofoconfig resume <id>        Resume a specific session by id
fofoconfig doctor             Re-run step-zero smoke tests
fofoconfig --help             This help
```

### Inside the session

```text
/help     Show command reference
/exit     Leave the session  (also: /quit, /q, Ctrl+D)
Alt+V     Paste a clipboard image (for the multimodal F7 feature)
Ctrl+V    Paste an image + text together
```

---

## 📚 Skills

FoFoConfig ships **6 built-in format-card skills** — each captures the *structure* of a config format (keys, syntax, gotchas, validators) without ever storing your values. Recall is instant; new formats are learned + cached on the fly.

| Skill | When it applies | Validator |
|---|---|---|
| 🌐 `nginx-config` | nginx.conf, sites-available/*, conf.d/*.conf | `nginx -t` |
| 🔑 `dotenv-files` | .env, .env.local, .env.production (NOT .env.example) | — (shell-parse heuristics) |
| 🔐 `ssh-client-config` | ~/.ssh/config, /etc/ssh/ssh_config | `ssh -F <f> -G dummy` |
| 🎯 `git-config` | ~/.gitconfig, ~/.config/git/config, .git/config | `git config --file <f> --list` |
| 🐳 `docker-compose` | compose.yaml, docker-compose.yml | `docker compose -f <f> config --quiet` |
| ⚙️ `systemd-unit` | *.service, *.timer, *.socket, *.mount | `systemd-analyze verify <f>` |

Each skill has its own `SKILL.md` under `profile/skills/config-formats/` — readable, editable, [agentskills.io](https://agentskills.io)-compatible, shareable. Want to add one? [See Contributing](#-contributing).

### Learning new formats

Hand FoFoConfig a Caddyfile, a Traefik config, a Prometheus rule file — anything it doesn't recognize:

1. It searches the web for *general format terms* (never your file contents).
2. Distills the structure into a new format-card skill.
3. Caches under `~/.fofoconfig/skills/config-formats/<new-format>/`.
4. Uses it immediately; on future encounters, instant recall.

---

## 🏗️ Architecture

<p align="center">
  <img src="docs/assets/architecture.png" alt="FoFoConfig architecture — POSIX launcher → Python ACP client → hermes acp → operator-chosen OpenAI-compatible endpoint" width="720" />
</p>

```
fofoconfig (POSIX launcher)
    │
    │   chat / edit / explain
    ▼
fofoconfig_acp_client.py (Python, uses bundled `acp` SDK)
    │   ▲
    │   │  stdio JSON-RPC 2.0
    │   │  (session_update, read_text_file, write_text_file,
    │   │   request_permission ← F3/F6 gate lives here)
    ▼   │
hermes acp (Hermes Agent in ACP server mode)
    │
    │   OpenAI-compatible HTTP
    ▼
your chosen Gemma 4 endpoint
    (local Ollama / remote llama.cpp / vLLM / LM Studio / your own)
```

**Key design choices:**

- **Bring-your-own endpoint.** No bundled inference. Setup wizard verifies your choice. Refuses cloud LLM providers. [Why?](docs/design.plan.md#why-acp-and-not-the-alternatives-we-considered)
- **ACP, not a wrapper.** Interactive sessions are driven via the [Agent Client Protocol](https://agentclientprotocol.com/) (the same standard Zed, VS Code, and JetBrains use for editor integrations). The diff-and-confirm gate is enforced at the **protocol layer** — the client receives a `request_permission` callback before any file write, renders the unified diff, and only returns approval after explicit operator `y/n`.
- **Thin layer over Hermes.** Persona + skills + setup wizard + ACP client. No reinvented wheels. Hermes provides the agent loop, redaction, checkpoints, session persistence, and a polished TUI.
- **Skills are portable.** Each is a Markdown file with YAML frontmatter following [agentskills.io](https://agentskills.io) — you can share them, fork them, publish them.

Deeper reading: [docs/Requirements-Specs.md](docs/Requirements-Specs.md) (the spec) · [docs/design.plan.md](docs/design.plan.md) (the implementation plan + lessons learned).

---

## ⚡ Performance notes

- **Default model: `gemma4:e4b-it-q8_0`** — 12 GB GGUF Q8, full multimodal, ~128K context. Best tool-call fidelity / size trade-off for the E-line.
- **Lighter: `gemma4:e4b`** (= `gemma4:e4b-it-q4_K_M`, 9.6 GB Q4) — smaller, slightly less reliable on tool calls.
- **Heavier: `gemma4:e4b-it-bf16`** (16 GB) or `gemma4:26b` (18 GB MoE, ~4B active, more capable).
- **MLX-tagged variants** (`-mlx`, `-mxfp8`, `-nvfp4`) are **text-only** on Ollama and won't satisfy the screenshot-paste feature. Stick to GGUF tags if you want F7.
- **Tool-call streaming** is currently disabled by default (`display.streaming: false`) for reliability with small models. Flip it on after `fofoconfig doctor` passes with streaming enabled if you want snappier output.

---

## 🩺 Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `fofoconfig` says "No endpoint configured yet" | Setup hasn't run, or was interrupted | `fofoconfig setup` |
| Setup probes fail at "Context length below 64K" | Model loaded with default num_ctx | Setup writes `ollama_num_ctx: 65536` automatically for Ollama. For non-Ollama endpoints, configure your server to load with ≥64K. |
| Agent says "permission denied for that path" | Path-policy gate refused (e.g. `~/.ssh/id_rsa`) | Intentional. Edit `_DENY_PATH_PATTERNS` in `scripts/fofoconfig_acp_client.py` if you genuinely need it. |
| F7 / screenshot paste doesn't work | Endpoint serves a text-only model (often an `-mlx` Gemma 4 tag) | Switch to a GGUF tag (`gemma4:e4b-it-q8_0`). |
| `fofoconfig doctor` shows tool calling fails | Model variant or chat-template bug | Diagnose: `display.streaming: false`? No `<\|think\|>` in SOUL? Then step **up** in capability — `Q4 → Q8 → BF16 → 26B`. Don't step down. |
| Setup wizard refuses my endpoint | Hostname matches cloud-LLM blocklist (SH4) | Intentional. Verify it's actually a self-hosted endpoint, then re-run with `--i-know-what-im-doing` (will be logged to `MEMORY.md`). |

Anything else: open an [issue](https://github.com/Sweet-Papa-Technologies/FoFoConfig/issues) with `fofoconfig doctor` output attached.

---

## 🤝 Contributing

PRs welcome, particularly:

- 🧩 **New format-card skills.** Drop a `SKILL.md` under `profile/skills/config-formats/<name>/`. Match the frontmatter shape of the existing skills (see [SOUL.md format-card schema](profile/SOUL.md#format-card-schema-use-this-exact-frontmatter-for-every-new-format-card)). Test by copying into `~/.fofoconfig/skills/config-formats/` and starting a session.
- 🛡️ **Path-policy patterns.** Found a credential store we don't deny? Add a pattern to `_DENY_PATH_PATTERNS` in `scripts/fofoconfig_acp_client.py` + a unit-test case.
- 🌍 **Cross-platform verification.** macOS Apple Silicon is verified day-one; Linux + WSL2 are authored cross-platform-aware but unverified. PRs that confirm-or-fix on those platforms are highly valuable.
- 📚 **Documentation.** Lessons learned, deployment notes, integration recipes for specific setups.

### Development setup

```sh
git clone https://github.com/Sweet-Papa-Technologies/FoFoConfig.git
cd FoFoConfig
./install.sh --no-setup           # installs Hermes + launcher without running setup
fofoconfig setup                  # configure an endpoint (or skip if you already have one)
fofoconfig doctor                 # 5/5 should pass
```

The implementation log + build-cycle lessons (every gotcha we hit and how we fixed it) lives in [`docs/design.plan.md`](docs/design.plan.md). The spec is in [`docs/Requirements-Specs.md`](docs/Requirements-Specs.md).

---

## 📜 License

Apache 2.0 — see [LICENSE](./LICENSE).

---

## 🙏 Credits

Built on the shoulders of:

- **[HermesAgent](https://github.com/NousResearch/hermes-agent)** (Nous Research) — the agent layer, skills system, redaction, checkpoints, ACP server.
- **[Gemma 4](https://ai.google.dev/gemma)** (Google DeepMind) — the model. Submitted to the **2026 Gemma 4 Challenge** under the "Build with Gemma 4" track.
- **[Ollama](https://ollama.com/)** — the easiest local inference on-ramp.
- **[Agent Client Protocol](https://agentclientprotocol.com/)** (Zed Industries + community) — the standard that makes the diff-and-confirm gate possible at the protocol layer.
- **[agentskills.io](https://agentskills.io)** — the skill format we extend.

Made by [Sweet Papa Technologies LLC](https://github.com/Sweet-Papa-Technologies).
