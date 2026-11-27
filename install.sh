#!/usr/bin/env zsh
# DietToken One-Command Setup & Configuration Helper for macOS / Linux.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
MCP_PY="$REPO_ROOT/scripts/local_shunt_mcp.py"
HOOK_PY="$REPO_ROOT/scripts/shunt_hook.py"

echo "========================================================"
echo "  DietToken Setup"
echo "  Repo: $REPO_ROOT"
echo "========================================================"

# 1. Detect Apple Silicon / system RAM and recommend preset
RECOMMENDED_PRESET="qwen3-8b"
if [[ "$(uname -s)" == "Darwin" ]]; then
  MEM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
  MEM_GB=$(( MEM_BYTES / 1073741824 ))
  if (( MEM_GB >= 28 )); then
    RECOMMENDED_PRESET="nemotron-3.5-lightning"
  fi
  echo "Detected macOS with ${MEM_GB} GB unified memory."
  echo "Recommended preset: ${RECOMMENDED_PRESET}"
else
  echo "Detected $(uname -s)."
fi
echo ""

# 2. Check optional local runtime tools
MISSING_BREW=()
if ! command -v llama-server >/dev/null 2>&1 && [[ ! -x "$HOME/local-llms/llama.cpp/build/bin/llama-server" ]]; then
  if command -v ollama >/dev/null 2>&1; then
    echo "  [INFO] Found Ollama ($(command -v ollama)). You can use DIET_TOKEN_BASE_URL=http://127.0.0.1:11434/v1"
  else
    MISSING_BREW+=("llama.cpp")
  fi
fi
if ! command -v pdftotext >/dev/null 2>&1; then
  MISSING_BREW+=("poppler")
fi

if (( ${#MISSING_BREW[@]} > 0 )) && [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ "${1:-}" == "--brew" ]]; then
    echo "Installing ${MISSING_BREW[*]} via Homebrew..."
    brew install "${MISSING_BREW[@]}"
  else
    echo "  [TIP] Optional Homebrew tools not installed: ${MISSING_BREW[*]}"
    echo "        Run './install.sh --brew' or 'brew install ${MISSING_BREW[*]}' to install them."
  fi
  echo ""
fi

# 3. Build macOS menu bar app if on Darwin and clang is available
if [[ "$(uname -s)" == "Darwin" ]] && command -v clang >/dev/null 2>&1; then
  echo "Building macOS menu bar controller..."
  "$REPO_ROOT/projects/local-shunt-bar/build.sh"
  echo ""
fi

# 4. Run self-diagnostics
python3 "$REPO_ROOT/scripts/doctor.py"
echo ""

# 5. Print ready-to-copy agent wiring instructions with exact paths
cat <<EOF
--------------------------------------------------------
  Next Steps (Copy & Paste)
--------------------------------------------------------

1) Download & start your recommended local model (skip if using Ollama / LM Studio):
   "$REPO_ROOT/scripts/download_model.sh" $RECOMMENDED_PRESET
   "$REPO_ROOT/scripts/start_model.sh" $RECOMMENDED_PRESET

2) Wire into Claude Code:
   claude mcp add local-shunt -- python3 "$MCP_PY"

   And add to ~/.claude/settings.json under "hooks":
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Read",
           "hooks": [{ "type": "command", "command": "python3 \"$HOOK_PY\"" }]
         }
       ]
     }
   }

3) Or wire into Antigravity / Cursor / Codex CLI (MCP JSON):
   {
     "mcpServers": {
       "local-shunt": {
         "command": "python3",
         "args": ["$MCP_PY"]
       }
     }
   }
EOF
