#!/bin/sh
# install.sh — FoFoConfig installer (Spec v0.2 Stage A: slim, no inference layer).
# Idempotent: re-running upgrades in place.
#
# This script DOES NOT install Ollama, pull models, or assume any inference layer.
# After install, run `fofoconfig setup` to point FoFoConfig at your OpenAI-compatible
# Gemma 4 endpoint (local Ollama, LAN llama.cpp, your homelab GPU — your choice).
set -eu

# ---------- Constants ----------
HERMES_HOME="${HERMES_HOME:-$HOME/.fofoconfig}"
HERMES_MIN_VERSION="0.14.0"

log()  { printf '\033[1;34m[fofo]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[fofo]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fofo]\033[0m %s\n' "$*" >&2; exit 1; }

# Compare two dotted versions: returns 0 if $1 >= $2.
version_ge() {
  printf '%s\n%s\n' "$2" "$1" | sort -V -C 2>/dev/null
}

# Flags
RUN_SETUP=1
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-setup) RUN_SETUP=0; shift ;;
      -h|--help)
        cat <<'EOF'
install.sh — FoFoConfig installer (Spec v0.2 Stage A).

USAGE:
  ./install.sh [--no-setup]

FLAGS:
  --no-setup    Install everything except invoking `fofoconfig setup` at the end.
                Use when scripting the install separately from the endpoint config.
EOF
        exit 0 ;;
      *) die "Unknown flag: $1 (try --help)" ;;
    esac
  done
}

# ---------- Phase 1: Preflight ----------
detect_platform() {
  case "$(uname -s)" in
    Darwin)
      [ "$(uname -m)" = "arm64" ] || warn "Non-Apple-Silicon Mac: nothing platform-specific blocks you, just FYI."
      PLATFORM=macos ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then PLATFORM=wsl2
      else PLATFORM=linux; fi ;;
    MINGW*|MSYS*|CYGWIN*)
      die "Run this script *inside* WSL2, not a Windows shell. See README." ;;
    *) die "Unsupported OS: $(uname -s)" ;;
  esac
  log "Platform: $PLATFORM"
}

# ---------- Phase 2: Hermes ----------
install_hermes() {
  if command -v hermes >/dev/null 2>&1; then
    hermes_ver=$(hermes --version 2>&1 | head -1 | sed -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    log "Hermes present: $hermes_ver"
    if ! version_ge "$hermes_ver" "$HERMES_MIN_VERSION"; then
      warn "Hermes $hermes_ver is older than required $HERMES_MIN_VERSION."
      log "Upgrading Hermes..."
      if command -v pipx >/dev/null 2>&1; then pipx upgrade hermes-agent || pipx install hermes-agent
      else python3 -m pip install --user --upgrade hermes-agent; fi
    fi
  else
    log "Installing Hermes (PyPI)..."
    if command -v pipx >/dev/null 2>&1; then pipx install hermes-agent
    else python3 -m pip install --user hermes-agent; fi
  fi
}

# ---------- Phase 3: Isolated profile ----------
setup_profile() {
  log "Setting up isolated profile at HERMES_HOME=$HERMES_HOME"
  mkdir -p "$HERMES_HOME/skills/config-formats" "$HERMES_HOME/memories" "$HERMES_HOME/sessions"
  cp "${SRC_DIR}/profile/config.yaml" "$HERMES_HOME/config.yaml"
  cp "${SRC_DIR}/profile/SOUL.md"     "$HERMES_HOME/SOUL.md"
  cp -R "${SRC_DIR}/profile/skills/config-formats/." \
        "$HERMES_HOME/skills/config-formats/"
  [ -f "$HERMES_HOME/memories/MEMORY.md" ] || \
    printf '# FoFoConfig agent memory\n' > "$HERMES_HOME/memories/MEMORY.md"
  [ -f "$HERMES_HOME/memories/USER.md" ]   || \
    printf '# Operator notes\n' > "$HERMES_HOME/memories/USER.md"
  # Verify the config is parseable by Hermes (with placeholder values).
  if HERMES_HOME="$HERMES_HOME" hermes config check >/dev/null 2>&1; then
    log "Hermes accepts the base config.yaml"
  else
    warn "Hermes config check reported issues — run \`HERMES_HOME=$HERMES_HOME hermes config check\` to inspect."
  fi
}

# ---------- Phase 4: Launcher (records SRC_DIR for `fofoconfig doctor`) ----------
install_launcher() {
  target="/usr/local/bin/fofoconfig"
  if ! install -m 0755 /dev/null "$target" 2>/dev/null; then
    target="$HOME/.local/bin/fofoconfig"; mkdir -p "$(dirname "$target")"
  fi
  sed "s|@FOFO_REPO_DIR@|${SRC_DIR}|g" "${SRC_DIR}/bin/fofoconfig" > "$target"
  chmod 0755 "$target"
  LAUNCHER_PATH="$target"
  log "Launcher installed: $target"
  case ":$PATH:" in
    *":$(dirname "$target"):"*) ;;
    *) warn "$(dirname "$target") is not in your PATH. Add it or call \`$target\` directly." ;;
  esac
}

# ---------- Phase 5: Setup wizard (Stage B) ----------
run_setup() {
  log "Launching endpoint setup wizard..."
  echo
  if "$LAUNCHER_PATH" setup; then
    log "FoFoConfig installed and configured. Run: fofoconfig"
  else
    warn "Setup wizard exited non-zero. Re-run any time with: fofoconfig setup"
    warn "Or verify the current state with: fofoconfig doctor"
    exit 1
  fi
}

# ---------- Main ----------
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
parse_args "$@"
detect_platform
install_hermes
setup_profile
install_launcher

if [ "$RUN_SETUP" = "1" ]; then
  run_setup
else
  log "Skipping setup (--no-setup). Run: fofoconfig setup"
  log "FoFoConfig base install complete."
fi
