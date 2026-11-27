#!/usr/bin/env python3
"""
DietToken (Local Shunt) — Universal PreToolUse Hook (fail-open).
Supports BOTH Antigravity and Claude Code PreToolUse JSON schemas, and probes
any OpenAI-compatible local server (/v1/models: llama-server, mlx_lm, Ollama, LM Studio).
Targeted reads (StartLine/EndLine or offset/limit) always pass through.
"""
import json
import os
import sys
import urllib.request
from pathlib import Path

BASE_URL = (
    os.getenv("DIET_TOKEN_BASE_URL")
    or os.getenv("LOCAL_SHUNT_BASE_URL")
    or "http://127.0.0.1:8080/v1"
)
LINE_THRESHOLD = int(
    os.getenv("DIET_TOKEN_MAX_LINES")
    or os.getenv("LOCAL_SHUNT_MAX_LINES")
    or "350"
)
HEALTH_URL = (
    os.getenv("DIET_TOKEN_HEALTH_URL")
    or os.getenv("LOCAL_SHUNT_HEALTH_URL")
    or f"{BASE_URL.rstrip('/')}/models"
)
SKIP_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp",
    ".mp4", ".mp3", ".wav", ".zip", ".gguf",
}
PAUSE_FLAG = Path(
    os.getenv("DIET_TOKEN_PAUSE_FILE", "~/.config/local-shunt/paused")
).expanduser()


def is_paused() -> bool:
    if os.getenv("DIET_TOKEN_FORCE_ALIVE") == "1":
        return False
    return PAUSE_FLAG.exists()


def local_server_alive() -> bool:
    force = os.getenv("DIET_TOKEN_FORCE_ALIVE")
    if force == "1":
        return True
    if force == "0":
        return False
    try:
        req = urllib.request.Request(
            HEALTH_URL,
            headers={"Authorization": "Bearer local"},
        )
        with urllib.request.urlopen(req, timeout=0.35) as resp:
            return resp.status == 200
    except Exception:
        return False


def emit_allow(is_claude: bool) -> None:
    if is_claude:
        # Empty exit 0 lets Claude Code proceed normally without overriding user permissions
        return
    print(json.dumps({"decision": "allow"}))


def emit_deny(is_claude: bool, reason: str) -> None:
    if is_claude:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }))
    else:
        print(json.dumps({"decision": "deny", "reason": reason}))


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        print(json.dumps({"decision": "allow"}))
        return

    is_claude = "tool_input" in payload or "hook_event_name" in payload

    if is_paused():
        emit_allow(is_claude)
        return

    if is_claude:
        tool_name = payload.get("tool_name")
        if tool_name not in (None, "Read", "read_file"):
            emit_allow(is_claude=True)
            return
        args = payload.get("tool_input") or {}
        if args.get("offset") is not None or args.get("limit") is not None:
            emit_allow(is_claude=True)
            return
        path_str = args.get("file_path") or args.get("path") or ""
    else:
        tool_call = payload.get("toolCall") or {}
        args = tool_call.get("args") or {}
        if args.get("StartLine") is not None or args.get("EndLine") is not None:
            emit_allow(is_claude=False)
            return
        path_str = args.get("Path") or ""

    if not path_str:
        emit_allow(is_claude)
        return

    p = Path(path_str).expanduser()
    if not p.is_file() or p.suffix.lower() in SKIP_EXTENSIONS:
        emit_allow(is_claude)
        return

    is_pdf = p.suffix.lower() == ".pdf"
    line_count = 0
    if not is_pdf:
        try:
            with p.open("rb") as f:
                line_count = sum(1 for _ in f)
        except Exception:
            emit_allow(is_claude)
            return

        if line_count <= LINE_THRESHOLD:
            emit_allow(is_claude)
            return

    if not local_server_alive():
        emit_allow(is_claude)
        return

    reason_detail = "is a PDF" if is_pdf else f"has {line_count} lines (>{LINE_THRESHOLD})"
    range_hint = "offset and limit" if is_claude else "StartLine and EndLine"
    emit_deny(
        is_claude,
        (
            f"DietToken: {p.name} {reason_detail}. "
            f"Call MCP tool local_summarize_file(path='{p}', question='...') first to get a concise summary "
            f"with exact line ranges, then read only the lines you need using {range_hint}."
        ),
    )


if __name__ == "__main__":
    main()
