# DietToken

[![CI](https://github.com/drtomslens/diet-token/actions/workflows/ci.yml/badge.svg)](https://github.com/drtomslens/diet-token/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS / Apple Silicon](https://img.shields.io/badge/Platform-macOS%20%7C%20Apple%20Silicon-black)](https://github.com/drtomslens/diet-token)
[![Python 3.10+ | Zero Dependencies](https://img.shields.io/badge/Python-3.10%2B%20(stdlib%20only)-green)](scripts/local_shunt_core.py)

**Put your coding agent's context window on a 98% diet.**

**DietToken** intercepts heavy bulk file reads (`>350` lines) and PDFs from cloud coding agents (**Claude Code**, **Antigravity**, **Codex CLI**, **Cursor**, **OpenCode**) and shunts them to a fast local model on your Mac (`llama.cpp`, **Ollama**, **LM Studio**, or **MLX**) — returning only a compact, line-cited summary (`L120–L145`) so your frontier cloud model keeps 100% of its tokens for architecture, editing, and hard debugging.

---

## Measured Benchmarks (32 GB M1 Max, 79 KB / 506-line LaTeX Manuscript)

| Scenario | Cloud Input Tokens | Local Runtime | Cloud Tokens Saved |
| :--- | :---: | :---: | :---: |
| **Without DietToken** (raw `Read`) | `~19,797 tok` | — | `0%` |
| **1. Cold local read** (1st question on file) | `~239 tok` | `121.7s` | **`98.8%` (`~19,558 tok` saved)** |
| **2. Follow-up question on same file** (KV-cache prefix reuse) | `~133 tok` | **`7.9s` (16x faster)** | **`99.3%` (`~19,664 tok` saved)** |
| **3. Repeat query on unchanged file** (`mtime`-verified cache) | `~284 tok` | **`< 0.1s` (instant)** | **`98.6%` (`~19,513 tok` saved)** |

*Tested with `NVIDIA-Nemotron-3.5-Lightning-30B-A3B` (`Q4_0`) via `llama-server` on a 32 GB MacBook Pro (M1 Max).*

---

## How It Works

```text
Cloud Coding Agent (Claude Opus/Sonnet, Gemini, GPT)
   │
   ├─► Small files (≤350 lines) & targeted line slices ──► Read directly (fast, lossless)
   │
   └─► Large files (>350 lines) & PDFs ──► PreToolUse hook (shunt_hook.py)
                                               │  (auto-fails open if local server is off)
                                               ▼
                                    local-shunt stdio MCP server
                                               │
                                               ▼
                               Local LLM (llama.cpp / Ollama / MLX / LM Studio)
                                 • 0 cloud tokens spent on raw file or PDF
                                 • Returns bullet summary + exact line ranges (L42–L68)
                                 • Agent then reads ONLY the 20–50 lines it needs to edit
```

Why **read-only shunting** instead of local code generation? Frontier cloud models excel at multi-file edits and subtle debugging, while 80–90% of wasted context tokens come from ingesting huge files, PDFs, and logs. DietToken keeps code writing on your frontier model and offloads bulk reading locally.

---

## 2-Minute Quickstart

Clone the repository anywhere on your Mac (outside cloud-synced folders like iCloud/Google Drive is recommended for clean git operations):

```zsh
git clone https://github.com/drtomslens/diet-token.git ~/diet-token
cd ~/diet-token
./install.sh
```

`./install.sh` detects your Mac's unified memory, builds `/Applications/DietToken.app` (the native macOS menu bar toggle), runs `scripts/doctor.py`, and prints copy-paste config blocks with your exact paths.

Now pick **Path A** (if you already use Ollama / LM Studio) or **Path B** (dedicated `llama.cpp` / `mlx-lm` server for maximum speed):

### Path A: Already Using Ollama or LM Studio (30 Seconds, Zero New Downloads)

If you already run **Ollama** (`http://127.0.0.1:11434/v1`) or **LM Studio** (`http://127.0.0.1:1234/v1`), DietToken works immediately — it auto-detects the loaded model from `/v1/models`:

```zsh
# Example with Ollama:
ollama pull qwen3:8b
export DIET_TOKEN_BASE_URL="http://127.0.0.1:11434/v1"
python3 scripts/doctor.py --require-server
```

*(When configuring your MCP server and hook below, pass `"DIET_TOKEN_BASE_URL": "http://127.0.0.1:11434/v1"` in `"env"`.)*

### Path B: Maximum Apple Silicon Speed via `llama.cpp` (Recommended)

1. **Install `llama.cpp` and `poppler` (fast PDF text extraction):**
   ```zsh
   brew install llama.cpp poppler
   ```
2. **Download the preset matching your Mac's RAM** (saved to `~/local-llms/models/`, resumable via `curl` or `hf`):
   ```zsh
   # For 16 GB or 24 GB Macs (~5.0 GB download):
   ./scripts/download_model.sh qwen3-8b

   # For 32 GB+ Macs (~18 GB download, 128K context, 3B active MoE — recommended):
   ./scripts/download_model.sh nemotron-3.5-lightning
   ```
3. **Start the local server** (or click the preset in the **macOS Menu Bar App**):
   ```zsh
   ./scripts/start_model.sh qwen3-8b                  # 16 GB / 24 GB Mac
   # or
   ./scripts/start_model.sh nemotron-3.5-lightning    # 32 GB+ Mac
   ```

---

## Choosing a Model for Your MacBook

| Mac Unified Memory | Preset Name | Model & Quant | Disk / RAM | Context | Source on Hugging Face |
| :--- | :--- | :--- | :---: | :---: | :--- |
| **16 GB – 24 GB** (M1–M4 Air / Pro) | `qwen3-8b` | `Qwen3-8B-Q4_K_M.gguf` | `~5.0 GB` | `32K` | [`unsloth/Qwen3-8B-GGUF`](https://huggingface.co/unsloth/Qwen3-8B-GGUF) |
| **32 GB+** (M1–M4 Max / Pro) ⭐ | `nemotron-3.5-lightning` | `NVIDIA-Nemotron-3.5-Lightning-30B-A3B-Q4_0.gguf` | `~18 GB` | `128K` | [`bartowski/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF`](https://huggingface.co/bartowski/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF) |
| **32 GB+** (Multimodal option) | `gemma-4-26b-a4b` | `gemma-4-26B-A4B-it-Q4_0.gguf` | `~16 GB` | `64K` | [`unsloth/gemma-4-26B-A4B-it-GGUF`](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF) |

> **Alternative Backend — Apple MLX (`mlx-lm`):**  
> `scripts/start_model.sh` also supports `BACKEND="mlx"`. Install `pip install mlx-lm`, set `BACKEND="mlx"` and `MLX_MODEL="mlx-community/..."` in a `configs/<name>.env` file, and launch with `./scripts/start_model.sh <name>`.

---

## Wiring Into Your Coding Agent

### 1. Claude Code
Register the MCP server:
```zsh
claude mcp add local-shunt -- python3 "$HOME/diet-token/scripts/local_shunt_mcp.py"
```
To **automatically intercept** `>350`-line `Read` calls and PDFs, add the `PreToolUse` hook to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$HOME/diet-token/scripts/shunt_hook.py\""
          }
        ]
      }
    ]
  }
}
```

### 2. Google Antigravity
Add `local-shunt` to your MCP servers config and register `scripts/shunt_hook.py` as a `PreToolUse` hook on `read_file`:
```json
{
  "mcpServers": {
    "local-shunt": {
      "command": "python3",
      "args": ["/Users/<you>/diet-token/scripts/local_shunt_mcp.py"]
    }
  }
}
```
Also add a global rule at `~/.gemini/config/rules/local-shunt.md` so every new Antigravity session calls `local_summarize_file` / `local_search_files` on the first try:
```markdown
When `local-shunt` is available, always call `local_summarize_file` first for PDFs and large files (>200 lines), and `local_search_files` for broad multi-file searches. Only fall back to `read_file` for small files or targeted line edits.
```

### 3. Codex CLI / Cursor / OpenCode
Add the stdio MCP server in your client's MCP configuration (`~/.codex/config.toml`, `.cursor/mcp.json`, or `opencode.json`). Even without a `PreToolUse` hook, you can instruct your agent in `AGENTS.md` / `.cursorrules`:
> *"For files over 350 lines or PDFs, call `local_summarize_file` or `local_search_files` first, then read only targeted line ranges."*

---

## Native macOS Menu Bar Controller

`./install.sh` (or `./projects/local-shunt-bar/build.sh`) compiles a lightweight, zero-dependency Objective-C/Cocoa menu bar app (`/Applications/DietToken.app` — no Xcode app or paid Apple Developer account needed):

```zsh
open /Applications/DietToken.app
```

- Shows **`● Nemotron`** / **`● Qwen3`** / **`● Gemma`** when active on `:8080`, or **`○ DietToken`** when stopped.
- Displays cumulative **cloud tokens saved** across sessions.
- **One-click preset switching** (auto-discovers any `.env` file in `configs/`) and **Stop Server** to free unified memory immediately when you unplug or game.
- **Fail-open guarantee:** When you click **Stop Server**, `shunt_hook.py` detects within `350ms` that no local server is running and lets your cloud agent read files normally — zero broken workflows.

---

## Diagnostics, Token Stats & Configuration

Check your installation anytime:
```zsh
python3 scripts/doctor.py
```

View cumulative cloud token savings across sessions:
```zsh
python3 scripts/shunt_stats.py
```

### Environment Variables (All Optional)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DIET_TOKEN_BASE_URL` | `http://127.0.0.1:8080/v1` | OpenAI-compatible base URL (`:11434/v1` for Ollama, `:1234/v1` for LM Studio) |
| `DIET_TOKEN_MODEL` | *(auto-detected from `/v1/models`)* | Explicit model ID override |
| `DIET_TOKEN_MAX_LINES` | `350` | Line-count threshold before `shunt_hook.py` intercepts a text/code file |
| `DIET_TOKEN_MAX_CHARS` | `160000` | Max numbered characters sent per call (`~40K` tokens) |
| `DIET_TOKEN_TIMEOUT` | `300` | Request timeout in seconds for large cold reads |

*(Hot-reload built in: edits to `scripts/local_shunt_core.py` take effect on the very next MCP tool call without restarting your IDE or conversation.)*

---

## Credits & Inspiration

Inspired by Spotify Engineering's open-source **`shunt`** plugin in [`spotify/portal-ai-plugins`](https://github.com/spotify/portal-ai-plugins) (`plugins/shunt/`) and their engineering blog post [Portal by Spotify cut my Claude Code token usage by 90%](https://engineering.atspotify.com/2026/9/portal-by-spotify-cut-my-claude-code-token-usage-by-90). While Spotify's original plugin routes large reads through Portal CLI and cloud worker models, **DietToken** adapts the `PreToolUse` interception pattern to run 100% locally on Apple Silicon via `llama.cpp` / Ollama / MLX + stdio MCP + KV-cache prefix reuse + a native macOS menu bar controller.

## License

[MIT](LICENSE)
