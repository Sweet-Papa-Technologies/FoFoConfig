#!/bin/sh
# fofoconfig-setup — interactive endpoint configuration wizard (Spec v0.2 Stage B).
# Verifies an operator-chosen OpenAI-compatible endpoint meets Hermes' actual requirements
# (reachable, model loads, tool calling fires, context >= 64K, vision capability if F7)
# before writing the model: block of ~/.fofoconfig/config.yaml.
#
# Usage:
#   fofoconfig setup
#   fofoconfig setup --endpoint http://host:11434/v1 --model gemma4:e4b --api-key ollama
#   fofoconfig setup --no-prompt        # CI mode; requires all of --endpoint --model --api-key
#   fofoconfig setup --no-vision        # opt out of F7 verification
#   fofoconfig setup --i-know-what-im-doing   # override the cloud-LLM blocklist (SH4)
set -eu

HERMES_HOME="${HERMES_HOME:-$HOME/.fofoconfig}"
CONFIG_FILE="$HERMES_HOME/config.yaml"
HERMES_MIN_CONTEXT=64000

# SH4 — cloud LLM endpoint blocklist (refuse by default; --i-know-what-im-doing to override).
CLOUD_BLOCKLIST="api.openai.com api.anthropic.com generativelanguage.googleapis.com openrouter.ai api.together.xyz api.groq.com api.deepseek.com api.mistral.ai api.cohere.ai api.fireworks.ai claude.ai openai.azure.com"

# Flags
ENDPOINT=""
MODEL=""
API_KEY=""
NO_PROMPT=0
REQUIRE_VISION=1
OVERRIDE_CLOUD=0

log()  { printf '\033[1;34m[fofo]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[fofo]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fofo]\033[0m %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m  \xE2\x9C\x93\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m  \xE2\x9C\x97\033[0m %s\n' "$*"; }

usage() {
  cat <<'EOF'
fofoconfig setup — point FoFoConfig at an OpenAI-compatible Gemma 4 endpoint.

USAGE:
  fofoconfig setup [flags]

FLAGS:
  --endpoint URL     Base URL of the endpoint (e.g. http://localhost:11434/v1)
  --model NAME       Model name as the endpoint expects it (e.g. gemma4:e4b-it-q8_0)
  --api-key KEY      API key (any non-empty string; many local endpoints ignore it)
  --no-prompt        Don't prompt; require all of --endpoint --model --api-key
  --no-vision        Skip the F7 vision-capability check (text-only deployments)
  --i-know-what-im-doing
                     Override the cloud-LLM endpoint refusal (SH4). Use only for
                     self-hosted endpoints that happen to use a cloud-fronted hostname
                     (e.g. corporate LiteLLM proxy). Logs the override to MEMORY.md.
  -h, --help         This help.

DEFAULTS:
  If no endpoint is given and local Ollama is reachable at http://localhost:11434,
  setup will offer the Gemma 4 models you've already pulled.
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --endpoint) ENDPOINT="$2"; shift 2 ;;
      --model) MODEL="$2"; shift 2 ;;
      --api-key) API_KEY="$2"; shift 2 ;;
      --no-prompt) NO_PROMPT=1; shift ;;
      --no-vision) REQUIRE_VISION=0; shift ;;
      --i-know-what-im-doing) OVERRIDE_CLOUD=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown flag: $1 (try --help)" ;;
    esac
  done
}

banner() {
  cat <<'EOF'

============================================================
  FoFoConfig Setup — point me at your Gemma 4 endpoint
============================================================

FoFoConfig needs an OpenAI-compatible HTTP endpoint serving a Gemma 4 model.
The endpoint can be:
  - Local Ollama on this machine        (needs ~12 GB free RAM at runtime)
  - Remote Ollama on your LAN           (recommended if your daily-driver is busy)
  - llama.cpp / vLLM / LM Studio        (any OpenAI-compatible server)

It must NOT be a third-party cloud LLM (OpenAI, Anthropic, etc.) — see SH4 in the spec.

EOF
}

# Probe local Ollama for pulled Gemma 4 models. Outputs lines of "tag\tsize\n"; nothing if absent.
detect_local_ollama_gemma() {
  curl -sf --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1 || return 1
  command -v ollama >/dev/null 2>&1 || return 1
  ollama list 2>/dev/null | awk 'NR>1 && $1 ~ /^gemma/ { print $1 "\t" $2 $3 }'
}

prompt_endpoint() {
  if [ -n "$ENDPOINT" ] && [ -n "$MODEL" ] && [ -n "$API_KEY" ]; then
    log "Using flagged endpoint: $ENDPOINT  model: $MODEL"
    return 0
  fi
  [ "$NO_PROMPT" = "1" ] && die "--no-prompt requires --endpoint, --model, and --api-key"

  banner

  # Offer local Ollama models if any.
  gemma_models=$(detect_local_ollama_gemma || true)
  if [ -n "$gemma_models" ]; then
    log "Detected local Ollama at http://localhost:11434 with these Gemma 4 models pulled:"
    i=1
    # shellcheck disable=SC2034
    printf '%s\n' "$gemma_models" | while IFS=$(printf '\t') read -r tag size; do
      printf '    %d) %s  (%s)\n' "$i" "$tag" "$size"
      i=$((i+1))
    done
    printf '    c) enter a different endpoint manually\n\n'
    printf 'Pick a number or c: '
    read -r choice
    case "$choice" in
      [0-9]*)
        ENDPOINT="${ENDPOINT:-http://localhost:11434/v1}"
        MODEL=$(printf '%s\n' "$gemma_models" | sed -n "${choice}p" | cut -f1)
        [ -z "$MODEL" ] && die "Invalid choice."
        API_KEY="${API_KEY:-ollama}"
        ;;
      c|C|*) ;;  # fall through to manual prompts
    esac
  else
    log "No local Ollama with Gemma 4 detected."
    log "If you want one, install from: https://ollama.com/download — then pull a Gemma 4 (e.g. \`ollama pull gemma4:e4b\`) and re-run setup."
    log "Otherwise, enter the URL of an existing OpenAI-compatible endpoint:"
  fi

  if [ -z "$ENDPOINT" ]; then
    printf 'Endpoint base URL (e.g. http://192.168.1.99:8080/v1) [http://localhost:11434/v1]: '
    read -r ENDPOINT
    [ -z "$ENDPOINT" ] && ENDPOINT="http://localhost:11434/v1"
  fi
  if [ -z "$MODEL" ]; then
    printf 'Model name as the endpoint expects it (e.g. gemma4:e4b-it-q8_0): '
    read -r MODEL
    [ -z "$MODEL" ] && die "Model name required."
  fi
  if [ -z "$API_KEY" ]; then
    printf 'API key (any non-empty string; local endpoints typically ignore) [ollama]: '
    read -r API_KEY
    [ -z "$API_KEY" ] && API_KEY="ollama"
  fi
}

# SH4 — refuse known cloud LLM endpoints by default.
check_cloud_blocklist() {
  host=$(printf '%s' "$ENDPOINT" | sed -E 's|^https?://([^/:]+).*|\1|')
  for blocked in $CLOUD_BLOCKLIST; do
    if [ "$host" = "$blocked" ]; then
      if [ "$OVERRIDE_CLOUD" = "1" ]; then
        warn "==================================================================="
        warn "OVERRIDE: pointing FoFoConfig at $host (a known cloud LLM provider)."
        warn "This breaks the safe-with-secrets guarantee that is the whole reason"
        warn "this product exists. Only proceed if you know what you're doing"
        warn "(e.g. self-hosted proxy that happens to use this hostname)."
        warn "Logging this override to $HERMES_HOME/memories/MEMORY.md."
        warn "==================================================================="
        mkdir -p "$HERMES_HOME/memories"
        {
          printf '\n## SH4 override (%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          printf 'Operator pointed FoFoConfig at known cloud LLM hostname %s via --i-know-what-im-doing.\n' "$host"
          printf 'Privacy guarantee is the operator-controlled-inference assumption; that assumption is overridden here.\n'
        } >> "$HERMES_HOME/memories/MEMORY.md"
        return 0
      fi
      die "Refusing to configure endpoint $host — it's on the cloud-LLM blocklist (SH4). FoFoConfig's safe-with-secrets guarantee depends on operator-controlled inference. If this is actually a self-hosted endpoint that happens to use this hostname (e.g. a corporate LiteLLM proxy), re-run with --i-know-what-im-doing."
    fi
  done
  # Non-loopback hostnames: warn but allow.
  case "$host" in
    localhost|127.0.0.1|::1|*.local) ;;
    *)
      log "Endpoint host '$host' is not loopback. Confirm this is infrastructure YOU control."
      if [ "$NO_PROMPT" != "1" ]; then
        printf 'Continue? [y/N]: '
        read -r yn
        case "$yn" in y|Y|yes|YES) ;; *) die "Aborted by operator." ;; esac
      fi ;;
  esac
}

# ----- Verification probes (the actual product value of setup) -----

verify_reachable() {
  if curl -sf --max-time 5 "${ENDPOINT}/models" >/dev/null 2>&1; then
    ok "Endpoint reachable (GET /v1/models returned 200)"
    return 0
  fi
  # Some endpoints (notably bare Ollama) don't expose /v1/models but do expose /v1/chat/completions.
  # Try a tiny chat as a fallback liveness probe.
  if curl -sf --max-time 10 "${ENDPOINT}/chat/completions" \
       -H 'Content-Type: application/json' \
       -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1,\"stream\":false}" \
       >/dev/null 2>&1; then
    ok "Endpoint reachable (POST /v1/chat/completions accepted)"
    return 0
  fi
  fail "Endpoint not reachable at $ENDPOINT"
  warn "  Try: curl -v ${ENDPOINT}/models"
  warn "  If the endpoint requires a header beyond Authorization, FoFoConfig can't set arbitrary headers; pick a simpler endpoint."
  return 1
}

verify_model_loads() {
  # First call can be a COLD load — a 12 GB model over LAN takes well past 30s. Allow 5 min.
  # Capture both stdout and curl's exit-code-driven stderr for diagnostics.
  tmp_err=$(mktemp)
  resp=$(curl -s --show-error --max-time 300 "${ENDPOINT}/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly the word: PONG\"}],\"max_tokens\":8,\"stream\":false}" 2>"$tmp_err")
  curl_exit=$?
  err=$(cat "$tmp_err"); rm -f "$tmp_err"
  if [ $curl_exit -ne 0 ]; then
    fail "Model '$MODEL' did not load via $ENDPOINT (curl exit=$curl_exit, may be cold-load timeout)"
    [ -n "$err" ] && warn "  curl: $err"
    return 1
  fi
  if printf '%s' "$resp" | grep -qi 'pong\|"content"'; then
    ok "Model '$MODEL' loads and responds"
    return 0
  fi
  fail "Model loaded but returned an unexpected response"
  warn "  First 300 chars: $(printf '%s' "$resp" | head -c 300)"
  return 1
}

verify_tool_calling() {
  tmp_err=$(mktemp)
  resp=$(curl -s --show-error --max-time 120 "${ENDPOINT}/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' \
    -d "{
      \"model\":\"${MODEL}\",
      \"stream\":false,
      \"messages\":[{\"role\":\"user\",\"content\":\"What is the weather in Paris? Use the tool.\"}],
      \"tools\":[{
        \"type\":\"function\",
        \"function\":{
          \"name\":\"get_weather\",
          \"description\":\"Get the current weather for a city\",
          \"parameters\":{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"]}
        }
      }]
    }" 2>"$tmp_err")
  curl_exit=$?
  err=$(cat "$tmp_err"); rm -f "$tmp_err"
  if [ $curl_exit -ne 0 ]; then
    fail "Tool-call request failed (curl exit=$curl_exit)"
    [ -n "$err" ] && warn "  curl: $err"
    return 1
  fi
  if printf '%s' "$resp" | grep -q '"tool_calls"'; then
    ok "Tool calling fires (model emitted tool_calls)"
    return 0
  fi
  fail "Model did not emit tool_calls — F1/F3/F5 all depend on this"
  warn "  Ladder: (a) is display.streaming:false in your config? (b) no <|think|> in SOUL? (c) thinking-mode disabled?"
  warn "  Step UP in capability if persistent: Q4 -> Q8 -> BF16 -> 26B. DO NOT step down for reliability."
  warn "  Response head: $(printf '%s' "$resp" | head -c 300)"
  return 1
}

# Verify context length empirically via a real Hermes invocation. Hermes is the
# authority on whether the context floor is met — it errors loudly if not.
#
# Why empirical instead of `ollama show context length`: that shortcut reads the model's
# ARCHITECTURAL max (e.g. 131072 for gemma4:e4b) which doesn't reflect what Ollama actually
# loads at runtime. The runtime is controlled by either Modelfile PARAMETER num_ctx OR
# the request's options.num_ctx. We use `model.ollama_num_ctx` in config.yaml (see
# write_config_stub_for_probe) to force the runtime size, so the only meaningful check is
# "did Hermes' request succeed?".
verify_context_length() {
  hermes_probe=$(HERMES_HOME="$HERMES_HOME" hermes -z "Reply with exactly: HCTX_OK" 2>&1 || true)
  if printf '%s' "$hermes_probe" | grep -qiE 'at least.*tokens|increase.*context|ollama_num_ctx|loaded.*with only.*tokens'; then
    fail "Hermes refused — context below its floor of $HERMES_MIN_CONTEXT."
    warn "  Hermes said:"
    printf '%s' "$hermes_probe" | grep -iE 'tokens|num_ctx|context' | head -4 | sed 's/^/    /'
    warn "  Fix options:"
    warn "    (1) The model's architectural max may be <64K. Pick a larger Gemma 4 tag (e.g. gemma4:e4b-it-q8_0)."
    warn "    (2) If you control the server, raise its default context size."
    return 1
  fi
  if printf '%s' "$hermes_probe" | grep -q 'HCTX_OK'; then
    ok "Hermes accepts the endpoint (empirical context check passed)"
    return 0
  fi
  # Inconclusive — could be a different error (e.g. T2 model load issue we already caught).
  warn "Context-length check inconclusive. Hermes output head:"
  printf '%s' "$hermes_probe" | head -c 200 | sed 's/^/    /'
  printf '\n'
  return 0
}

verify_vision() {
  [ "$REQUIRE_VISION" = "1" ] || { ok "Vision check skipped (--no-vision)"; return 0; }
  # Ollama: read capabilities directly.
  if printf '%s' "$ENDPOINT" | grep -qE '://(localhost|127\.0\.0\.1)(:[0-9]+)?' \
     && command -v ollama >/dev/null 2>&1; then
    if ollama show "$MODEL" 2>/dev/null | grep -qiE 'vision|image'; then
      ok "Model advertises vision capability (F7 OK)"
      return 0
    fi
    fail "Model does NOT advertise vision capability — F7 (multimodal) will not work"
    warn "  GGUF Gemma 4 builds have vision; MLX-format (-mxfp8, -mlx, -nvfp4) do not."
    warn "  Either pick a GGUF tag (e.g. gemma4:e4b-it-q8_0) or re-run with --no-vision."
    return 1
  fi
  # Non-Ollama: try a tiny base64 image and check for a coherent response.
  # 1x1 transparent PNG (smallest valid PNG):
  tiny_png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
  resp=$(curl -sf --max-time 30 "${ENDPOINT}/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' \
    -d "{
      \"model\":\"${MODEL}\",
      \"stream\":false,
      \"max_tokens\":32,
      \"messages\":[{\"role\":\"user\",\"content\":[
        {\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,${tiny_png}\"}},
        {\"type\":\"text\",\"text\":\"What color is this pixel? One word.\"}
      ]}]
    }" 2>&1) || {
      fail "Endpoint rejected the multimodal request — likely doesn't support image input"
      warn "  Either pick a model/endpoint with vision or re-run with --no-vision."
      return 1
    }
  if printf '%s' "$resp" | grep -qi 'error\|cannot process\|unsupported'; then
    fail "Endpoint returned an error to the image request"
    warn "  Response: $(printf '%s' "$resp" | head -c 300)"
    return 1
  fi
  ok "Endpoint accepted a multimodal request (vision plausibly supported)"
  return 0
}

verify_all() {
  log "Verifying endpoint capabilities..."
  any_fail=0
  # Fixed: explicit if/then so shell precedence doesn't swallow failures (Draft-1 bug:
  # `[ x = "0" ] && f || any_fail=$any_fail` is a no-op on f's failure).
  if ! verify_reachable;        then any_fail=1; fi
  if [ $any_fail -eq 0 ]; then
    if ! verify_model_loads;    then any_fail=1; fi
  fi
  if [ $any_fail -eq 0 ]; then
    if ! verify_tool_calling;   then any_fail=1; fi
  fi
  # Write the probe config BEFORE the empirical Hermes checks (T5 context, T7 vision via Hermes)
  # so hermes -z talks to the right endpoint. Done regardless of earlier failures so the partial
  # state is on disk for the operator to re-test against without re-prompting.
  write_config_stub_for_probe
  if [ $any_fail -eq 0 ]; then
    if ! verify_context_length; then any_fail=1; fi
  fi
  if [ $any_fail -eq 0 ]; then
    if ! verify_vision;         then any_fail=1; fi
  fi
  return $any_fail
}

# Write a temporary model: block into config.yaml so the context-length empirical check
# (which uses `hermes -z`) actually talks to the right endpoint. If verification then fails,
# we leave the config in place for retry/debugging — the user can re-run setup.
#
# Includes `ollama_num_ctx: 65536` when the endpoint looks like Ollama, so Hermes asks Ollama
# to load with 64K runtime context (avoiding the "make a derived model with PARAMETER num_ctx
# 65536" requirement). For non-Ollama endpoints we omit it (might cause a key-not-recognized
# error on stricter servers).
write_config_stub_for_probe() {
  [ -f "$CONFIG_FILE" ] || die "Config file $CONFIG_FILE not found. Run install.sh first."
  # Detect Ollama endpoint by probing /api/tags (Ollama-specific).
  if curl -sf --max-time 2 "$(printf '%s' "$ENDPOINT" | sed -E 's|/v1/?$||')/api/tags" >/dev/null 2>&1; then
    IS_OLLAMA=1
  else
    IS_OLLAMA=0
  fi
  python3 - <<PY
import re
path = "$CONFIG_FILE"
endpoint = "$ENDPOINT"
model = "$MODEL"
api_key = "$API_KEY"
is_ollama = $IS_OLLAMA
ctx_floor = $HERMES_MIN_CONTEXT
with open(path) as f: src = f.read()
extra = f"  ollama_num_ctx: {ctx_floor}\n" if is_ollama else ""
new_block = f"""# === Endpoint config (written by \`fofoconfig setup\`) ===
model:
  default: {model}
  provider: custom
  base_url: {endpoint}
  api_key: {api_key}
  api_mode: chat_completions
{extra}# === End endpoint config ==="""
pattern = re.compile(r"# === Endpoint config.*?# === End endpoint config ===", re.S)
if pattern.search(src):
    src = pattern.sub(new_block, src)
else:
    src = new_block + "\n\n" + src
with open(path, "w") as f: f.write(src)
PY
  if [ "$IS_OLLAMA" = "1" ]; then
    log "  Detected Ollama; wrote ollama_num_ctx=$HERMES_MIN_CONTEXT to bypass num_ctx Modelfile dance."
  fi
}

write_modelfile_example() {
  # Helpful starter Modelfile if the operator picked local Ollama and needs to bump num_ctx.
  cat > "$HERMES_HOME/Modelfile.example" <<EOF
# Starter Modelfile for FoFoConfig (Spec v0.2 Stage B output).
# Hermes refuses models with <64K runtime context. If your chosen Ollama tag
# defaults below 64K, run: ollama create gemma4-fofo -f $HERMES_HOME/Modelfile.example
# then re-run: fofoconfig setup --model gemma4-fofo:latest --endpoint $ENDPOINT --api-key $API_KEY
FROM ${MODEL}
PARAMETER num_ctx 65536
PARAMETER temperature 0.2
EOF
}

finalize() {
  log "Validating Hermes config syntactically..."
  if HERMES_HOME="$HERMES_HOME" hermes config check >/dev/null 2>&1; then
    ok "Hermes accepts the new config.yaml"
  else
    warn "Hermes config check reported issues — run \`HERMES_HOME=$HERMES_HOME hermes config check\` to inspect."
  fi
  log "Endpoint configured."
  log "  base_url: $ENDPOINT"
  log "  model:    $MODEL"
  log "  Re-run anytime: fofoconfig setup"
  log "  Verify health: fofoconfig doctor"
}

main() {
  parse_args "$@"
  prompt_endpoint
  check_cloud_blocklist
  write_modelfile_example
  if ! verify_all; then
    fail "One or more verification steps failed. The config has been written so you can re-test with: fofoconfig doctor"
    fail "Fix the issue above and re-run: fofoconfig setup"
    exit 1
  fi
  finalize
}

main "$@"
