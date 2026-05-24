#!/bin/sh
# scripts/smoke-tests.sh — Step-zero verification (Spec v0.2 §9).
# Reads the configured endpoint from $HERMES_HOME/config.yaml and verifies it meets
# every requirement Hermes actually has (not just what the docs claim).
#
# Returns 0 if all critical tests pass. Non-zero exit aborts install / fails doctor.
# Callable standalone or via `fofoconfig doctor`.
set -u

HERMES_HOME="${HERMES_HOME:-$HOME/.fofoconfig}"
CONFIG_FILE="$HERMES_HOME/config.yaml"
HERMES_MIN_CONTEXT=64000
SRC_DIR="${SRC_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

PASS=0; FAIL=0
ok()   { printf '\033[1;32m  OK\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '\033[1;31m FAIL\033[0m  %s\n    %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
warn() { printf '\033[1;33m WARN\033[0m  %s\n    %s\n' "$1" "$2"; }

# Pull endpoint values out of config.yaml. Minimal awk so we don't need PyYAML.
if [ ! -f "$CONFIG_FILE" ]; then
  printf 'No config at %s — run install.sh first.\n' "$CONFIG_FILE" >&2; exit 1
fi
# Parse YAML keys nested under `model:`. Use stateful awk (range syntax collapses to one line
# here because awk's start/end ranges check both patterns against the same line).
_parse_model_key() {
  awk -v key="$1" '
    /^model:/ { in_model=1; next }
    /^[a-zA-Z_]/ { in_model=0 }
    in_model && $1 == key":" {
      sub("^[[:space:]]+" key ":[[:space:]]+", "")
      print; exit
    }
  ' "$CONFIG_FILE"
}
MODEL=$(_parse_model_key default)
ENDPOINT=$(_parse_model_key base_url)
API_KEY=$(_parse_model_key api_key)

echo
echo "FoFoConfig — step-zero smoke tests"
echo "  HERMES_HOME: $HERMES_HOME"
echo "  endpoint:    $ENDPOINT"
echo "  model:       $MODEL"
echo

if [ "$MODEL" = "PLEASE_RUN_FOFOCONFIG_SETUP" ]; then
  bad "T0 Setup" "No endpoint configured yet. Run: fofoconfig setup"
  echo; echo "Smoke tests: 0 passed, 1 failed."; exit 1
fi

# T1 — Endpoint reachable
if curl -sf --max-time 5 "${ENDPOINT}/models" >/dev/null 2>&1; then
  ok "T1 Endpoint reachable at ${ENDPOINT} (GET /v1/models)"
elif curl -sf --max-time 10 "${ENDPOINT}/chat/completions" \
       -H 'Content-Type: application/json' \
       -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1,\"stream\":false}" \
       >/dev/null 2>&1; then
  ok "T1 Endpoint reachable at ${ENDPOINT} (POST /v1/chat/completions accepted)"
else
  bad "T1 Endpoint" "Unreachable at ${ENDPOINT}. Try: curl -v ${ENDPOINT}/models"
fi

# T2 — Model loads
T2_RESP=$(curl -sf --max-time 30 "${ENDPOINT}/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' \
  -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: PONG\"}],\"max_tokens\":8,\"stream\":false}" 2>&1 || true)
if printf '%s' "$T2_RESP" | grep -qi 'pong\|"content"'; then
  ok "T2 Model '$MODEL' loads and responds"
else
  bad "T2 Model load" "No coherent response. First 200 chars: $(printf '%s' "$T2_RESP" | head -c 200)"
fi

# T3 — Tool calling fires (single biggest risk per spec §11).
T3_RESP=$(curl -sf --max-time 30 "${ENDPOINT}/chat/completions" \
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
  }" 2>&1 || true)
if printf '%s' "$T3_RESP" | grep -q '"tool_calls"'; then
  ok "T3 Tool calling fires (model emitted tool_calls via OpenAI-compat endpoint)"
else
  bad "T3 Tool calling" "No tool_calls. Diagnose: display.streaming:false, no <|think|> in SOUL, current chat template. Step UP (Q4 -> Q8 -> BF16) NOT down for reliability."
fi

# T4 — Modality (F7) assertion. Only meaningful for local Ollama (precise read) — for remote
# endpoints we do a base64 image probe as part of T5 instead.
if printf '%s' "$ENDPOINT" | grep -qE '://(localhost|127\.0\.0\.1)(:[0-9]+)?' \
   && command -v ollama >/dev/null 2>&1; then
  T4_INFO=$(ollama show "$MODEL" 2>/dev/null || true)
  if [ -z "$T4_INFO" ]; then
    warn "T4 Modality" "Model not visible via 'ollama show' (might be a derived/local-only tag). Skipping."
  elif printf '%s' "$T4_INFO" | grep -qiE 'vision|image'; then
    ok "T4 Model advertises vision capability (F7 OK)"
  else
    bad "T4 Modality" "Model is TEXT-ONLY. F7 multimodal won't work. Use a GGUF Gemma 4 tag (e.g. gemma4:e4b-it-q8_0), not MLX-format."
  fi
else
  warn "T4 Modality" "Non-Ollama endpoint — modality check deferred to T6 image probe."
fi

# T5 — Context length >= Hermes floor.
# Empirical via `hermes -z` — Hermes errors loudly if context is below its floor.
T5_OUT=$(HERMES_HOME="$HERMES_HOME" hermes -z "Reply with exactly: HCTX_OK" 2>&1 || true)
if printf '%s' "$T5_OUT" | grep -qiE 'at least.*tokens|increase.*context|num_ctx'; then
  bad "T5 Context length" "Hermes refused: context below ${HERMES_MIN_CONTEXT}. Increase via Modelfile (PARAMETER num_ctx 65536) or pick a model with higher default."
elif printf '%s' "$T5_OUT" | grep -q 'HCTX_OK'; then
  ok "T5 Hermes accepts the endpoint (empirical context check passed)"
else
  warn "T5 Context length" "Inconclusive — Hermes responded but not as expected. First 200: $(printf '%s' "$T5_OUT" | head -c 200)"
fi

# T6 — Redaction (SH1). Critical: includes precondition assertion so a Hermes error
# (e.g. context-too-small) can't masquerade as "redaction works" (Draft 1 false-positive).
FIXTURE_DIR=$(mktemp -d)
cat > "$FIXTURE_DIR/.env" <<'EOF'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
DATABASE_URL=postgres://admin:hunter2@db.example.com:5432/app
EOF
T6_OUT=$(HERMES_HOME="$HERMES_HOME" hermes -z "Use read_file on $FIXTURE_DIR/.env and report ONLY the line count as a number." 2>&1 || true)
if ! printf '%s' "$T6_OUT" | grep -qE '\<3\>'; then
  bad "T6 Redaction (precondition)" "Agent didn't report the expected line count of 3 — likely never ran read_file. Tail: $(printf '%s' "$T6_OUT" | tail -2)"
elif printf '%s' "$T6_OUT" | grep -q 'AKIAIOSFODNN7EXAMPLE' \
  || printf '%s' "$T6_OUT" | grep -q 'wJalrXUtnFEMI/K7MDENG'; then
  bad "T6 Redaction" "Raw AWS key visible in agent output. Redaction may be off or the file-tool gap (#363) regressed."
elif printf '%s' "$T6_OUT" | grep -q 'hunter2'; then
  bad "T6 Redaction" "DB password visible in agent output."
else
  ok "T6 Redactor masks AWS keys and DB password in file-tool output (and agent did read the file)"
fi
if grep -rq 'AKIAIOSFODNN7EXAMPLE' "$HERMES_HOME/logs/" 2>/dev/null; then
  bad "T6 Redaction (logs)" "Key persisted in logs. Verify security.redact_secrets: true."
fi
rm -rf "$FIXTURE_DIR"

# T7 — Multimodal image probe (best-effort, only if fixture exists).
if [ -f "${SRC_DIR}/scripts/fixtures/nginx-error.png" ]; then
  B64=$(base64 < "${SRC_DIR}/scripts/fixtures/nginx-error.png" | tr -d '\n')
  T7_RESP=$(curl -sf --max-time 60 "${ENDPOINT}/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' \
    -d "{
      \"model\":\"${MODEL}\",
      \"stream\":false,
      \"max_tokens\":64,
      \"messages\":[{\"role\":\"user\",\"content\":[
        {\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,${B64}\"}},
        {\"type\":\"text\",\"text\":\"Describe this image briefly.\"}
      ]}]
    }" 2>&1 || true)
  if printf '%s' "$T7_RESP" | grep -qiE 'nginx|error|config|web|server|text|image'; then
    ok "T7 Endpoint accepts image input and produces a plausible description"
  else
    warn "T7 Multimodal" "Image input didn't produce a recognisable description. F7 may need to be demoted."
  fi
else
  printf '\033[1;33m SKIP\033[0m  T7 Multimodal: no fixture image at scripts/fixtures/nginx-error.png.\n'
fi

echo
echo "Smoke tests: $PASS passed, $FAIL failed."
[ "$FAIL" -eq 0 ] || exit 1
