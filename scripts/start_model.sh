#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <preset-name>"
  echo "Available presets in $AI_ROOT/configs:"
  ls -1 "$AI_ROOT/configs" | sed 's/\.env$//'
  exit 1
fi

PRESET="$AI_ROOT/configs/$1.env"
if [[ ! -f "$PRESET" ]]; then
  echo "Preset not found: $PRESET"
  exit 1
fi

source "$PRESET"

if [[ "$BACKEND" == "llama-server" ]]; then
  if [[ ! -f "$MODEL_FILE" ]]; then
    echo "Model file not found: $MODEL_FILE"
    echo "Download it into $MODEL_DIR (outside Google Drive) and verify MODEL_FILE in $PRESET."
    exit 1
  fi

  ARGS=(
    --model "$MODEL_FILE"
    --alias "$MODEL_NAME"
    --ctx-size "$CTX_SIZE"
    --parallel 1
    --batch-size 2048
    --ubatch-size 512
    --flash-attn on
    --cache-reuse 256
    --jinja
    --no-reasoning-preserve
    --temp "${TEMP:-0.8}"
    --top-p "${TOP_P:-0.95}"
    --top-k "${TOP_K:-40}"
    --min-p "${MIN_P:-0.0}"
    --reasoning-budget "${REASONING_BUDGET:--1}"
    --cache-type-k "$KV_CACHE_TYPE"
    --cache-type-v "$KV_CACHE_TYPE"
    --n-gpu-layers 999
    --host "$HOST"
    --port "$PORT"
  )

  if [[ -n "${MMPROJ_FILE:-}" && -f "${MMPROJ_FILE:-}" ]]; then
    ARGS+=(--mmproj "$MMPROJ_FILE")
  fi

  LLAMA_BIN="$HOME/local-llms/llama.cpp/build/bin/llama-server"
  if [[ ! -x "$LLAMA_BIN" ]]; then
    LLAMA_BIN="llama-server"
  fi

  echo "Starting $MODEL_NAME via $LLAMA_BIN on http://$HOST:$PORT/v1 ..."
  exec "$LLAMA_BIN" "${ARGS[@]}"

elif [[ "$BACKEND" == "mlx" ]]; then
  echo "Starting $MODEL_NAME via mlx_lm.server on http://$HOST:$PORT/v1 ..."
  exec env MLX_ENABLE_TF32=0 mlx_lm.server --model "$MLX_MODEL" --host "$HOST" --port "$PORT"
else
  echo "Unsupported BACKEND: $BACKEND"
  exit 1
fi
