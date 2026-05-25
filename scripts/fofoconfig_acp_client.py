#!/usr/bin/env python3
"""fofoconfig ACP client — drives a Hermes ACP-mode session from a launcher.

Why this exists: `hermes chat` (interactive TUI) has no flag to pre-seed the first user
message. ACP (Agent Client Protocol) is the architecturally correct way for an external
process to drive a Hermes session — we get programmatic session start, message send,
streamed responses, and (critically) the diff/confirm gate as a client-side callback
at the protocol boundary (write_text_file, request_permission).

Run via Hermes' venv Python (the launcher bakes that path in):
    /path/to/hermes/venv/bin/python3 scripts/fofoconfig_acp_client.py [--seed "..."]

The script spawns `hermes acp` as a subprocess, initializes the ACP protocol, creates a
session, optionally sends a seed message, then enters an interactive loop. Streaming
agent output is rendered live. File writes go through an F3 gate (backup → diff → y/n).

See docs/Requirements-Specs.md §7-§9, docs/design.plan.md, and the agentclientprotocol.com
spec for the protocol details.
"""

from __future__ import annotations

import argparse
import asyncio
import difflib
import fnmatch
import os
import shutil
import sys
from pathlib import Path
from typing import Any

import acp
from acp import (
    Client,
    ReadTextFileResponse,
    RequestPermissionResponse,
    WriteTextFileResponse,
    PROTOCOL_VERSION,
    spawn_agent_process,
    text_block,
)
from acp.exceptions import RequestError


# ---------- terminal rendering helpers ----------

class Color:
    """Tiny ANSI helper — no extra deps."""
    RESET = "\033[0m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    BLUE = "\033[1;34m"
    GREEN = "\033[1;32m"
    YELLOW = "\033[1;33m"
    RED = "\033[1;31m"
    CYAN = "\033[1;36m"
    GREY = "\033[90m"


def fofo(msg: str) -> None:
    print(f"{Color.BLUE}[fofo]{Color.RESET} {msg}", file=sys.stderr, flush=True)


def warn(msg: str) -> None:
    print(f"{Color.YELLOW}[fofo]{Color.RESET} {msg}", file=sys.stderr, flush=True)


def err(msg: str) -> None:
    print(f"{Color.RED}[fofo]{Color.RESET} {msg}", file=sys.stderr, flush=True)


# ---------- path policy (Vuln 2 fix from the security review) ----------

# Paths the agent must NOT read or write without an explicit operator override at the agent layer.
# These are high-value secret stores common on dev machines. The threat model: a prompt-injected
# agent (via SOUL rule 7's acknowledged risk) could otherwise be told to read ~/.ssh/id_rsa and
# exfiltrate it via the `web` toolset. Refusing at the protocol boundary closes that loop.
#
# Patterns use fnmatch glob syntax. Paths are absolute-resolved before matching.
_DENY_PATH_PATTERNS: tuple[str, ...] = (
    # SSH private keys (allow ~/.ssh/config, known_hosts, *.pub — block id_*, *.pem)
    "*/.ssh/id_*",
    "*/.ssh/*_rsa",
    "*/.ssh/*_dsa",
    "*/.ssh/*_ecdsa",
    "*/.ssh/*_ed25519",
    "*/.ssh/*.pem",
    "*/.ssh/agent.*",
    # AWS / GCP / Azure credentials
    "*/.aws/credentials",
    "*/.aws/sso/cache/*",
    "*/.config/gcloud/credentials.db",
    "*/.config/gcloud/application_default_credentials.json",
    "*/.azure/accessTokens.json",
    "*/.azure/msal_token_cache.*",
    # Kubernetes / Docker
    "*/.kube/config",
    "*/.docker/config.json",
    # Browser / CLI auth stores
    "*/.config/gh/hosts.yml",
    "*/.config/gh/config.yml",
    "*/.netrc",
    "*/.npmrc",
    "*/.pypirc",
    "*/.cargo/credentials*",
    # GPG
    "*/.gnupg/*.kbx",
    "*/.gnupg/*.key",
    "*/.gnupg/private-keys-v1.d/*",
    # System secret stores (often root-only, but defense-in-depth)
    "/etc/shadow",
    "/etc/sudoers",
    "/etc/sudoers.d/*",
    "/etc/ssh/ssh_host_*_key",
    # Password manager / keyring files
    "*/.password-store/*",
    "*/.config/keepassxc/*.kdbx",
    "*/.local/share/keyrings/*",
)


def _check_path_policy(path: Path) -> str | None:
    """Return None if path is allowed; otherwise return a denial reason string.

    Compared against `_DENY_PATH_PATTERNS` (fnmatch). Operates on the resolved absolute path
    so symlink-based bypasses don't work. Conservative: when in doubt, allow — the diff/confirm
    gate at request_permission is the second line of defense for writes.
    """
    s = str(path)
    for pattern in _DENY_PATH_PATTERNS:
        if fnmatch.fnmatch(s, pattern):
            return f"path matches deny pattern '{pattern}'"
    return None


# ---------- the client ----------

class FoFoClient(Client):
    """Renders agent output and enforces the F3/F5/F6 gates as protocol callbacks."""

    def __init__(self) -> None:
        super().__init__()
        # Track per-tool-call rendering state so progress updates don't double-print.
        self._tool_titles: dict[str, str] = {}
        # Newline tracking: agent text streams as chunks; we want a clean prompt afterwards.
        self._mid_agent_line = False
        # (Earlier drafts had a background-task spinner here. Removed: writing \r to stderr
        # while agent text streamed to stdout caused cursor races — half-erased lines, blank
        # output, garbled prompts. The streaming text + tool-call markers (▸) are already the
        # progress indicator. Silent gaps are short and tolerable; UI honesty beats fake motion.)

    # --- streaming output ---
    async def session_update(self, session_id: str, update: Any, **_: Any) -> None:  # noqa: ARG002
        """Handle every kind of streaming update from the agent."""
        kind = type(update).__name__
        if kind == "AgentMessageChunk":
            self._render_block(getattr(update, "content", None), color=None)
        elif kind == "AgentThoughtChunk":
            self._render_block(getattr(update, "content", None), color=Color.GREY)
        elif kind in ("ToolCallStart", "ToolCallProgress"):
            self._render_tool_call(update)
        elif kind == "AgentPlanUpdate":
            self._render_plan(update)
        elif kind in ("AvailableCommandsUpdate", "ConfigOptionUpdate",
                      "SessionInfoUpdate", "UsageUpdate", "CurrentModeUpdate"):
            pass  # metadata; ignore
        elif kind == "UserMessageChunk":
            pass  # agent echoing our message back; ignore
        else:
            warn(f"unhandled session update: {kind}")

    def _render_block(self, block: Any, color: str | None) -> None:
        """Render a single content block (note: ACP `content` is a single block, not a list)."""
        if block is None:
            return
        btype = type(block).__name__
        text = getattr(block, "text", None)
        if text:
            if color:
                print(f"{color}{text}{Color.RESET}", end="", flush=True)
            else:
                print(text, end="", flush=True)
            self._mid_agent_line = True
            return
        # Non-text blocks (image, audio, resource): describe tersely so we don't lose them.
        if btype != "TextContentBlock":
            print(f"{Color.DIM}[{btype}]{Color.RESET}", end="", flush=True)
            self._mid_agent_line = True

    def _render_tool_call(self, update: Any) -> None:
        tcid = getattr(update, "tool_call_id", None) or getattr(update, "id", None)
        title = getattr(update, "title", None)
        status = getattr(update, "status", None)
        if not tcid:
            return
        if self._mid_agent_line:
            print()
            self._mid_agent_line = False
        if title and tcid not in self._tool_titles:
            self._tool_titles[tcid] = title
            print(f"{Color.CYAN}▸ {title}{Color.RESET}", flush=True)
        if status:
            status_str = getattr(status, "value", str(status))
            if status_str in ("completed", "failed"):
                color = Color.GREEN if status_str == "completed" else Color.RED
                t = self._tool_titles.get(tcid, "tool call")
                print(f"  {color}└ {status_str}: {t}{Color.RESET}", flush=True)

    def _render_plan(self, update: Any) -> None:
        if self._mid_agent_line:
            print()
            self._mid_agent_line = False
        entries = getattr(update, "entries", None) or []
        if not entries:
            return
        print(f"{Color.DIM}Plan:{Color.RESET}", flush=True)
        for e in entries:
            content = getattr(e, "content", "")
            status = getattr(e, "status", "")
            status_str = getattr(status, "value", str(status))
            marker = {"completed": "[x]", "in_progress": "[~]"}.get(status_str, "[ ]")
            print(f"  {Color.DIM}{marker} {content}{Color.RESET}", flush=True)

    # --- file callbacks (F3 + F6 gates live here) ---
    async def read_text_file(
        self, path: str, session_id: str, limit: int | None = None,
        line: int | None = None, **_: Any
    ) -> ReadTextFileResponse:  # noqa: ARG002
        p = Path(path).expanduser().resolve()
        # Path policy gate (security review Vuln 2): refuse known secret-store paths even
        # though SOUL rule 7 + redactor are the in-prompt defenses. Defense-in-depth.
        denial = _check_path_policy(p)
        if denial:
            warn(f"refused agent read of {p}: {denial}")
            raise RequestError.invalid_request(
                f"FoFoConfig refused to read {p}: {denial}. If you need this read, edit "
                f"scripts/fofoconfig_acp_client.py _DENY_PATH_PATTERNS and re-run."
            )
        if not p.exists():
            raise RequestError.invalid_params(f"File not found: {p}")
        try:
            content = p.read_text()
        except UnicodeDecodeError:
            raise RequestError.invalid_params(f"File is not UTF-8 text: {p}")
        # Honor line/limit slicing if provided (ACP spec — agent may request a window).
        if line is not None:
            lines = content.splitlines(keepends=True)
            start = max(0, line - 1)
            end = start + limit if limit else len(lines)
            content = "".join(lines[start:end])
        elif limit is not None:
            content = content[:limit]
        return ReadTextFileResponse(content=content)

    async def write_text_file(
        self, content: str, path: str, session_id: str, **_: Any
    ) -> WriteTextFileResponse | None:  # noqa: ARG002
        """Silent executor — the F3 gate is upstream in request_permission.

        Why no second prompt: when Hermes wants to write a file, it first sends
        request_permission with a FileEditToolCallContent showing the diff. Our
        callback there renders the diff, gets y/n, and (if approved) writes the
        .fofobak backup BEFORE returning approval. By the time write_text_file
        fires, the operator has already consented. Asking again would double-prompt
        and (worse) exhaust stdin in scripted flows.

        Edge case: if Hermes ever calls write_text_file WITHOUT prior
        request_permission (a "trusted write" path), we'd execute silently.
        That's acceptable for v1 because config.yaml has approvals.mode: manual,
        which forces gating for everything Hermes considers dangerous. Logged as
        v2 backlog: track recent permission grants and double-check by path.
        """
        p = Path(path).expanduser().resolve()
        # Path policy gate (security review Vuln 2): refuse writes to deny-listed paths.
        denial = _check_path_policy(p)
        if denial:
            warn(f"refused agent write to {p}: {denial}")
            raise RequestError.invalid_request(
                f"FoFoConfig refused to write to {p}: {denial}. If you need this write, edit "
                f"scripts/fofoconfig_acp_client.py _DENY_PATH_PATTERNS and re-run."
            )
        if self._mid_agent_line:
            print()
            self._mid_agent_line = False
        # Defensive backup if request_permission didn't run (e.g. trusted-write path).
        if p.exists():
            try:
                p.read_text()  # verify text-readable
            except UnicodeDecodeError:
                raise RequestError.invalid_params(
                    f"Refusing to overwrite binary file: {p}"
                )
            backup = p.with_suffix(p.suffix + ".fofobak")
            if not backup.exists() or backup.stat().st_mtime < p.stat().st_mtime:
                try:
                    shutil.copy2(p, backup)
                    fofo(f"backup: {backup}")
                except Exception as e:
                    warn(f"could not write backup for {p}: {e}")
        p.write_text(content)
        fofo(f"wrote {p}")
        return WriteTextFileResponse()

    # --- permission callback (F3 + F5 + F6 gate) ---
    # Hermes routes file edits (the `patch` tool) AND dangerous shell commands through
    # request_permission. This is the universal protocol-level gate. We:
    #   - render unified diffs for FileEditToolCallContent (so the operator sees what's changing)
    #   - write the .fofobak backup BEFORE returning approval (F6)
    #   - accept y/n as sugar for "first allow option" / "first reject option"
    async def request_permission(
        self, options: list[Any], session_id: str, tool_call: Any, **_: Any
    ) -> RequestPermissionResponse:  # noqa: ARG002
        if self._mid_agent_line:
            print()
            self._mid_agent_line = False
        title = getattr(tool_call, "title", None) or "tool call"
        kind = getattr(tool_call, "kind", None)
        print(f"\n{Color.YELLOW}⚠ Permission requested:{Color.RESET} {title}")

        edit_paths_to_backup: list[tuple[Path, str]] = []
        # Render content blocks: diffs prominently, text inline, terminal mentions tersely.
        for content in getattr(tool_call, "content", None) or []:
            ctype = type(content).__name__
            if ctype == "FileEditToolCallContent":
                path = Path(getattr(content, "path", "")).expanduser().resolve()
                old_text = getattr(content, "old_text", "") or ""
                new_text = getattr(content, "new_text", "") or ""
                print(f"\n{Color.BOLD}─── diff for {path} ───{Color.RESET}")
                diff = "".join(difflib.unified_diff(
                    old_text.splitlines(keepends=True),
                    new_text.splitlines(keepends=True),
                    fromfile=str(path),
                    tofile=f"{path} (proposed)",
                    n=3,
                ))
                if not diff:
                    print(f"  {Color.DIM}(no textual change){Color.RESET}")
                else:
                    for line in diff.splitlines():
                        if line.startswith("+") and not line.startswith("+++"):
                            print(f"{Color.GREEN}{line}{Color.RESET}")
                        elif line.startswith("-") and not line.startswith("---"):
                            print(f"{Color.RED}{line}{Color.RESET}")
                        elif line.startswith("@@"):
                            print(f"{Color.CYAN}{line}{Color.RESET}")
                        else:
                            print(line)
                edit_paths_to_backup.append((path, old_text))
            elif ctype == "ContentToolCallContent":
                text = getattr(getattr(content, "content", None), "text", None)
                if text:
                    for line in text.splitlines()[:20]:
                        print(f"  {Color.DIM}{line}{Color.RESET}")
            elif ctype == "TerminalToolCallContent":
                tid = getattr(content, "terminal_id", "?")
                print(f"  {Color.DIM}(terminal: {tid}){Color.RESET}")

        # Categorize options so y/n can map intelligently.
        allow_opt = next((o for o in options if getattr(getattr(o, "kind", None), "value", str(getattr(o, "kind", ""))) in ("allow_once", "allow_always")), None)
        reject_opt = next((o for o in options if getattr(getattr(o, "kind", None), "value", str(getattr(o, "kind", ""))) in ("reject_once", "reject_always")), None)

        # Render options.
        print()
        for i, opt in enumerate(options, 1):
            name = getattr(opt, "name", None) or getattr(opt, "option_id", "?")
            ok = getattr(opt, "kind", "")
            ok_str = getattr(ok, "value", str(ok))
            print(f"  {i}) {name} {Color.DIM}({ok_str}){Color.RESET}")
        prompt = f"{Color.YELLOW}Approve? [y/N or 1-{len(options)}]:{Color.RESET} "
        choice = (await _ainput(prompt)).strip().lower()

        # Resolve the chosen option.
        picked = None
        if choice in ("y", "yes") and allow_opt is not None:
            picked = allow_opt
        elif choice in ("n", "no", "") and reject_opt is not None:
            picked = reject_opt
        else:
            try:
                idx = int(choice) - 1
                if 0 <= idx < len(options):
                    picked = options[idx]
            except ValueError:
                pass

        if picked is None:
            fofo("permission cancelled.")
            return RequestPermissionResponse(outcome={"outcome": "cancelled"})

        picked_kind = getattr(getattr(picked, "kind", None), "value", str(getattr(picked, "kind", "")))
        # F6 backup: if approving a file edit, write the .fofobak BEFORE returning.
        if picked_kind in ("allow_once", "allow_always") and edit_paths_to_backup:
            for path, old_text in edit_paths_to_backup:
                if path.exists():
                    backup = path.with_suffix(path.suffix + ".fofobak")
                    try:
                        shutil.copy2(path, backup)
                        fofo(f"backup: {backup}")
                    except Exception as e:
                        warn(f"could not write backup for {path}: {e}")

        return RequestPermissionResponse(
            outcome={"outcome": "selected", "option_id": picked.option_id}
        )

    # --- terminal callbacks: let Hermes handle terminal itself (it has its own subprocess mgmt) ---
    async def create_terminal(self, *args: Any, **kwargs: Any) -> Any:  # noqa: ARG002
        raise RequestError.method_not_found()

    async def terminal_output(self, *args: Any, **kwargs: Any) -> Any:  # noqa: ARG002
        raise RequestError.method_not_found()

    async def kill_terminal(self, *args: Any, **kwargs: Any) -> Any:  # noqa: ARG002
        raise RequestError.method_not_found()

    async def release_terminal(self, *args: Any, **kwargs: Any) -> Any:  # noqa: ARG002
        raise RequestError.method_not_found()


# ---------- async input helper ----------

async def _ainput(prompt: str) -> str:
    """Non-blocking input() so the asyncio loop keeps running."""
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, lambda: input(prompt))


# ---------- main ----------

async def run(seed: str | None, hermes_home: str) -> int:
    client = FoFoClient()
    env = {**os.environ, "HERMES_HOME": hermes_home}
    # Strip PYTHONPATH/HOME so the spawned Hermes uses its own venv cleanly.
    env.pop("PYTHONPATH", None)
    env.pop("PYTHONHOME", None)

    fofo(f"starting Hermes ACP session (HERMES_HOME={hermes_home})...")
    async with spawn_agent_process(client, "hermes", "acp", env=env) as (conn, proc):  # noqa: F841
        try:
            init_resp = await conn.initialize(
                protocol_version=PROTOCOL_VERSION,
                client_capabilities={
                    "fs": {"read_text_file": True, "write_text_file": True},
                    "terminal": False,  # let Hermes manage its own subprocesses
                },
            )
            fofo(f"protocol v{init_resp.protocol_version} negotiated.")
        except Exception as e:
            err(f"initialize failed: {e}")
            return 1

        # Create a new session in the operator's CWD so the agent's relative paths work.
        try:
            session = await conn.new_session(cwd=str(Path.cwd()), mcp_servers=[])
            session_id = session.session_id
            fofo(f"session: {session_id}")
        except Exception as e:
            err(f"new_session failed: {e}")
            return 1

        async def send(text: str) -> None:
            await conn.prompt(session_id=session_id, prompt=[text_block(text)])
            if client._mid_agent_line:
                print()
                client._mid_agent_line = False

        # Compact helper line. We reprint it right before each "You:" prompt so it sits at
        # the bottom of the scrollback — the streaming-terminal equivalent of a status bar
        # without needing a real TUI library. (A proper bottom bar would need prompt_toolkit
        # and a full screen-region rewrite; out of scope for v1.)
        HELPER = f"{Color.DIM}── /help · /exit · Ctrl+D to leave · Alt+V to paste an image ──{Color.RESET}"

        if seed:
            print()
            print(HELPER)
            print(f"{Color.BOLD}You:{Color.RESET} {seed}")
            try:
                await send(seed)
            except Exception as e:
                err(f"prompt failed: {e}")

        while True:
            try:
                print()
                print(HELPER)
                line = await _ainput(f"{Color.BOLD}You:{Color.RESET} ")
            except (EOFError, KeyboardInterrupt):
                print()
                break
            text = line.strip()
            if not text:
                continue
            if text in ("/exit", "/quit", "/q"):
                break
            if text in ("/help", "/h", "/?"):
                # Helper is already reprinted on each loop iteration — this just acknowledges.
                print(f"{Color.DIM}(helper line is reprinted before every prompt above){Color.RESET}")
                continue
            try:
                await send(text)
            except RequestError as e:
                err(f"prompt error: {e}")
            except Exception as e:
                err(f"unexpected error: {e}")

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="FoFoConfig ACP client — drives `hermes acp` from a launcher.",
    )
    parser.add_argument("--seed", help="Initial user message to send before the interactive loop.")
    parser.add_argument(
        "--hermes-home",
        default=os.environ.get("HERMES_HOME", os.path.expanduser("~/.fofoconfig")),
        help="HERMES_HOME for the spawned hermes acp (default: $HERMES_HOME or ~/.fofoconfig).",
    )
    args = parser.parse_args()
    try:
        return asyncio.run(run(args.seed, args.hermes_home))
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
