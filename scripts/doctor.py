#!/usr/bin/env python3
"""
DietToken Doctor — self-diagnostic check for MCP server, PreToolUse hooks,
PDF extraction, and local OpenAI-compatible LLM endpoint.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
MCP_SCRIPT = SCRIPT_DIR / "local_shunt_mcp.py"
HOOK_SCRIPT = SCRIPT_DIR / "shunt_hook.py"

BASE_URL = (
    os.getenv("DIET_TOKEN_BASE_URL")
    or os.getenv("LOCAL_SHUNT_BASE_URL")
    or "http://127.0.0.1:8080/v1"
)


def ok(msg: str) -> None:
    print(f"  [OK]   {msg}")


def info(msg: str) -> None:
    print(f"  [INFO] {msg}")


def fail(msg: str) -> None:
    print(f"  [FAIL] {msg}")


def check_python() -> bool:
    v = sys.version_info
    if (v.major, v.minor) >= (3, 10):
        ok(f"Python {v.major}.{v.minor}.{v.micro}")
        return True
    fail(f"Python >= 3.10 required (found {v.major}.{v.minor}.{v.micro})")
    return False


def check_pdf() -> bool:
    if shutil.which("pdftotext"):
        ok("PDF extraction: poppler (pdftotext)")
        return True
    for mod in ("pypdf", "PyPDF2", "fitz"):
        try:
            __import__(mod)
            ok(f"PDF extraction: Python module '{mod}'")
            return True
        except ImportError:
            pass
    if sys.platform == "darwin" and shutil.which("osascript"):
        ok("PDF extraction: macOS native PDFKit (install `brew install poppler` for faster large PDFs)")
        return True
    info("No PDF extractor found (optional: `brew install poppler` or `pip install pypdf`)")
    return True


def check_mcp_handshake() -> bool:
    init_req = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05"}}
    list_req = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
    stdin_payload = json.dumps(init_req) + "\n" + json.dumps(list_req) + "\n"

    res = subprocess.run(
        [sys.executable, str(MCP_SCRIPT)],
        input=stdin_payload,
        capture_output=True,
        text=True,
        timeout=10,
    )
    if res.returncode != 0:
        fail(f"MCP server exited with code {res.returncode}: {res.stderr.strip()}")
        return False

    lines = [ln.strip() for ln in res.stdout.splitlines() if ln.strip()]
    if len(lines) < 2:
        fail(f"MCP server returned incomplete output: {res.stdout!r}")
        return False

    tools_resp = json.loads(lines[1])
    tool_names = {t["name"] for t in tools_resp.get("result", {}).get("tools", [])}
    expected = {"local_summarize_file", "local_search_files"}
    if not expected.issubset(tool_names):
        fail(f"MCP tools missing: expected {expected}, got {tool_names}")
        return False

    ok("MCP stdio handshake & hot-reload tools verified (local_summarize_file, local_search_files)")
    return True


def check_hooks() -> bool:
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as tmp:
        tmp.write("\n".join(f"line {i}" for i in range(400)) + "\n")
        big_file = tmp.name

    env = dict(os.environ)
    env["DIET_TOKEN_FORCE_ALIVE"] = "1"

    try:
        # 1. Antigravity bulk read -> must deny
        ag_bulk = {"toolCall": {"args": {"Path": big_file}}}
        r1 = subprocess.run(
            [sys.executable, str(HOOK_SCRIPT)],
            input=json.dumps(ag_bulk),
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )
        out1 = json.loads(r1.stdout.strip())
        if out1.get("decision") != "deny":
            fail(f"Antigravity hook did not deny 400-line file: {out1}")
            return False

        # 2. Antigravity targeted read -> must allow
        ag_slice = {"toolCall": {"args": {"Path": big_file, "StartLine": 1, "EndLine": 50}}}
        r2 = subprocess.run(
            [sys.executable, str(HOOK_SCRIPT)],
            input=json.dumps(ag_slice),
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )
        out2 = json.loads(r2.stdout.strip())
        if out2.get("decision") != "allow":
            fail(f"Antigravity hook did not allow targeted read: {out2}")
            return False

        # 3. Claude Code bulk Read -> must deny via hookSpecificOutput
        cc_bulk = {"hook_event_name": "PreToolUse", "tool_name": "Read", "tool_input": {"file_path": big_file}}
        r3 = subprocess.run(
            [sys.executable, str(HOOK_SCRIPT)],
            input=json.dumps(cc_bulk),
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )
        out3 = json.loads(r3.stdout.strip())
        cc_dec = out3.get("hookSpecificOutput", {}).get("permissionDecision")
        if cc_dec != "deny":
            fail(f"Claude Code hook did not deny 400-line Read: {out3}")
            return False

        # 4. Claude Code targeted Read -> must exit 0 with empty stdout
        cc_slice = {
            "hook_event_name": "PreToolUse",
            "tool_name": "Read",
            "tool_input": {"file_path": big_file, "offset": 1, "limit": 50},
        }
        r4 = subprocess.run(
            [sys.executable, str(HOOK_SCRIPT)],
            input=json.dumps(cc_slice),
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )
        if r4.returncode != 0 or r4.stdout.strip() != "":
            fail(f"Claude Code hook did not pass through targeted Read cleanly: {r4.stdout!r}")
            return False

        ok("PreToolUse hook verified for both Claude Code and Antigravity schemas")
        return True
    finally:
        Path(big_file).unlink(missing_ok=True)


def check_live_server(require_server: bool) -> bool:
    models_url = f"{BASE_URL.rstrip('/')}/models"
    try:
        req = urllib.request.Request(models_url, headers={"Authorization": "Bearer local"})
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        models = [m.get("id", "?") for m in (data.get("data") or []) if isinstance(m, dict)]
        label = ", ".join(models) if models else "connected"
        ok(f"Local LLM reachable at {BASE_URL} (active model: {label})")
        return True
    except Exception:
        msg = (
            f"No local LLM currently running at {BASE_URL} "
            "(hook will fail-open safely until you start llama-server, Ollama, or LM Studio)"
        )
        if require_server:
            fail(msg)
            return False
        info(msg)
        return True


def main() -> None:
    require_server = "--require-server" in sys.argv
    print("DietToken Diagnostics")
    print("=" * 56)

    checks = [
        check_python(),
        check_pdf(),
        check_mcp_handshake(),
        check_hooks(),
        check_live_server(require_server),
    ]

    print("=" * 56)
    if all(checks):
        print("All DietToken checks passed.")
        sys.exit(0)
    else:
        print("One or more checks failed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
