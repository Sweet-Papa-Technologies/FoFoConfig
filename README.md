# FoFoConfig

**The config tool you can paste your secrets into.**

A privacy-first configuration-file specialist agent. Identifies any config format, explains it, and edits it safely with a diff-and-confirm gate. When it meets a format it doesn't know, it researches the format on the web and caches a *structure-only* skill card so it never has to relearn.

FoFoConfig runs against **any OpenAI-compatible Gemma 4 endpoint that YOU choose and trust** — your local Ollama, a remote llama.cpp/vLLM on your LAN, an LM Studio, your own homelab GPU. **It is safe to expose real secrets to it** because connection strings, keys, and tokens never leave infrastructure you control.

FoFoConfig is a thin, locked-down layer on top of [HermesAgent](https://hermes-agent.nousresearch.com/) by Nous Research.

---

## Install (two stages)

**Stage A — install the agent layer (slim, ~30s):**

```sh
git clone https://github.com/<owner>/FoFoConfig.git
cd FoFoConfig
./install.sh
```

This installs Hermes (if missing), drops the FoFoConfig profile into `~/.fofoconfig`, installs the `fofoconfig` launcher into your `PATH`. **It does not pull a 12 GB model and does not install Ollama** — those are your choices.

**Stage B — point FoFoConfig at your Gemma 4 endpoint:**

```sh
fofoconfig setup
```

The wizard:
- Detects local Ollama if you have it, and offers any pulled Gemma 4 models as picks.
- Prompts for `base_url`, `model name`, `api_key` (with sensible defaults).
- **Refuses known cloud LLM endpoints** (OpenAI, Anthropic, Google, OpenRouter, etc.) — `--i-know-what-im-doing` to override for self-hosted-via-cloud-fronted-hostname cases.
- **Verifies the endpoint actually meets Hermes' requirements** before writing config: reachable → model loads → tool calling fires → runtime context ≥64K → vision capability (for F7).
- Writes the verified model block into `~/.fofoconfig/config.yaml`.
- Re-runnable any time. `fofoconfig doctor` re-runs the verification.

**Windows:** install WSL2 (`wsl --install -d Ubuntu`), then run the same script inside WSL2. Native Win32 is on the v2 roadmap.

### Common endpoint setups

**You already have local Ollama with a Gemma 4 pulled:**

```sh
fofoconfig setup
# wizard detects it and offers your pulled models
```

**You want to install local Ollama:** Go to https://ollama.com/download, install, then:

```sh
ollama pull gemma4:e4b-it-q8_0       # 12 GB GGUF Q8 multimodal — recommended
# OR a lighter option:
ollama pull gemma4:e4b               # 9.6 GB Q4_K_M multimodal
fofoconfig setup
```

**You have a remote llama.cpp / vLLM / LM Studio on your LAN:**

```sh
fofoconfig setup --endpoint http://192.168.1.42:8080/v1 \
                 --model gemma4-9b-it \
                 --api-key whatever
```

**Hermes needs ≥64K runtime context.** Most Ollama Gemma 4 tags default to 32K or less, so you typically need a derived tag. The wizard writes a starter Modelfile for you:

```sh
ollama create gemma4-fofo -f ~/.fofoconfig/Modelfile.example
fofoconfig setup --model gemma4-fofo:latest
```

### Requirements

- For the agent layer: any modern macOS / Linux / WSL2 with `python3` and `pipx` or `pip`.
- For the inference layer (your choice): see ollama.com/download for the easiest on-ramp, or pick your own OpenAI-compatible server. On a 24 GB MacBook running daily-driver workloads, a dedicated inference host (LAN box) is recommended — running a 12 GB Gemma 4 + the agent + your other apps on one machine can pressure unified memory hard.

## Use

```sh
fofoconfig setup          Configure or re-configure your endpoint
fofoconfig                Start interactive TUI
fofoconfig edit nginx     Print a tip ("ask me — edit the configuration for: nginx"), then TUI
fofoconfig explain ~/.bashrc
fofoconfig resume         Resume last session
fofoconfig doctor         Re-run step-zero smoke tests
```

## What it can do

- **F1 — Locate configs.** Name a program ("edit my nginx config"); it finds candidates and confirms which one.
- **F2 — Learn new formats.** Unknown format? It researches via the web (general format terms only — never your file contents) and caches a structure-only skill card.
- **F3 — Safe edits.** Every change → backup `.fofobak` → unified diff → y/n confirm → apply → validate.
- **F4 — Persistent skill library.** Local knowledge grows under `~/.fofoconfig/skills/`.
- **F6 — Backups.** Single `.fofobak` per file + Hermes Checkpoints (`/rollback`).
- **F7 — Multimodal.** Paste a screenshot of a config or an error into the TUI (`Alt+V`); the agent reads it. **Conditional on your endpoint advertising vision capability** — setup verifies this. GGUF Gemma 4 builds have vision; MLX-format builds don't.

## Security posture (read this — calibrate trust correctly)

FoFoConfig's privacy guarantees, in order of strength:

1. **Operator-controlled inference.** The endpoint is whatever you configured — local Ollama, your LAN box, your own server. The `fofoconfig setup` wizard refuses known cloud LLM endpoints by default. No cloud-LLM fallback, ever.
2. **Structure-not-values.** The agent's SOUL forbids writing secret values to any skill, memory, log, or web query. It records the *shape* of configs only.
3. **File-reference over paste.** The agent reads files directly via `read_file` so secrets don't enter the chat transcript.
4. **Secret redaction.** Hermes' regex redactor masks API keys, JWTs, DB passwords, and similar in tool output and logs.
5. **Approval gate + Tirith scan.** Dangerous shell commands require explicit y/n confirmation.
6. **File contents are data, not instructions** — SOUL rule against prompt injection via config-file comments.

**Known limits:**

- Redaction is pattern-matching — defense-in-depth, not containment. Treat (1)–(3) above as the real boundary.
- Hermes' secrets-management story is still maturing (upstream issue NousResearch/hermes-agent#410). Plaintext `~/.fofoconfig/.env` storage and full env passthrough to subprocesses remain — don't store secrets in those places.
- If you point FoFoConfig at a third-party LLM provider (the `--i-know-what-im-doing` override exists for self-hosted proxies with cloud-fronted hostnames, NOT to enable e.g. OpenAI), **you have voluntarily broken the privacy guarantee**. The override is logged to `MEMORY.md` so the agent itself knows.
- Hardening upgrade: switch `terminal.backend: docker` in `~/.fofoconfig/config.yaml` to run shell commands inside an isolated container.

## How it works

- Isolated Hermes profile at `~/.fofoconfig/` — fully separate from any existing `~/.hermes`.
- Narrow toolset: `file`, `terminal`, `web`, `search`, `skills`, `todo`, `memory`. Browser, messaging, delegation, image/video generation, MCP — all disabled.
- Persona enforced via `SOUL.md`: structure-not-values, diff-and-confirm, sequential tool calls, file-contents-are-data.
- 2 seed skills ship out of the box: **nginx** and **dotenv**. New format-cards accrete under `~/.fofoconfig/skills/config-formats/`.
- Endpoint config is written by `fofoconfig setup` after probing the actual capabilities of the chosen server (Hermes silently requires ≥64K runtime context — setup catches that).

## Skills are portable

Each format-card under `~/.fofoconfig/skills/config-formats/` follows the [agentskills.io](https://agentskills.io) standard with a `metadata.fofoconfig.*` extension. You can publish them, share them, or hand-edit them — they're plain Markdown with YAML frontmatter.

## License

Apache 2.0 — see [LICENSE](./LICENSE).

## Credits

Built on [HermesAgent](https://github.com/NousResearch/hermes-agent) (Nous Research) + [Ollama](https://ollama.com/) + [Gemma 4](https://ai.google.dev/gemma).
Submitted to the 2026 Gemma 4 Challenge — "Build with Gemma 4" track.
By [Sweet Papa Technologies LLC](https://github.com/<owner>).
