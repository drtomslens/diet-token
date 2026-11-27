#!/usr/bin/env python3
"""
Local Shunt — Zero-dependency Stdio MCP Server Wrapper (with hot-reload).
Reloads local_shunt_core.py on every tools/list and tools/call so edits take
effect immediately without restarting the MCP server or conversation.
"""
import importlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import local_shunt_core  # noqa: E402


def send(msg: dict) -> None:
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue

        req_id = req.get("id")
        method = req.get("method", "")
        params = req.get("params", {}) or {}

        if method == "initialize":
            send({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": params.get("protocolVersion", "2024-11-05"),
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "local-shunt", "version": "0.2.0"},
                },
            })
        elif method == "notifications/initialized":
            continue
        elif method == "tools/list":
            try:
                importlib.reload(local_shunt_core)
            except Exception:
                pass
            send({"jsonrpc": "2.0", "id": req_id, "result": {"tools": local_shunt_core.TOOLS}})
        elif method == "tools/call":
            tool_name = params.get("name", "")
            tool_args = params.get("arguments", {}) or {}
            try:
                importlib.reload(local_shunt_core)
                text = local_shunt_core.handle_tool_call(tool_name, tool_args)
                send({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"content": [{"type": "text", "text": text}], "isError": False},
                })
            except Exception as e:
                send({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [{"type": "text", "text": f"Local Shunt error: {e}"}],
                        "isError": True,
                    },
                })
        elif req_id is not None:
            send({
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"},
            })


if __name__ == "__main__":
    main()
