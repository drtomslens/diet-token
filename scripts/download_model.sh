#!/usr/bin/env zsh
# Download GGUF model weights for any preset in configs/*.env straight from Hugging Face.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <preset-name>"
  echo ""
  echo "Available presets:"
  echo "  qwen3-8b                 (16 GB+ Mac — ~5.0 GB download)"
  echo "  nemotron-3.5-lightning   (32 GB+ Mac — ~18 GB download, 128K ctx, recommended)"
  echo "  gemma-4-26b-a4b          (32 GB+ Mac — ~16 GB download, 64K ctx)"
  exit 1
fi

PRESET="$REPO_ROOT/configs/$1.env"
if [[ ! -f "$PRESET" ]]; then
  echo "Error: Preset not found: $PRESET" >&2
  exit 1
fi

source "$PRESET"

if [[ -z "${HF_REPO:-}" || -z "${HF_FILE:-}" ]]; then
  echo "Error: $PRESET does not define HF_REPO and HF_FILE." >&2
  echo "Please download the GGUF file manually into: $MODEL_FILE" >&2
  exit 1
fi

mkdir -p "$MODEL_DIR"
TARGET="$MODEL_DIR/$HF_FILE"

if [[ -f "$TARGET" ]]; then
  echo "✓ Model already exists: $TARGET"
  exit 0
fi

echo "Downloading $HF_REPO / $HF_FILE"
echo "Destination: $TARGET"
echo ""

if command -v hf >/dev/null 2>&1; then
  hf download "$HF_REPO" "$HF_FILE" --local-dir "$MODEL_DIR"
elif command -v huggingface-cli >/dev/null 2>&1; then
  huggingface-cli download "$HF_REPO" "$HF_FILE" --local-dir "$MODEL_DIR"
else
  URL="https://huggingface.co/${HF_REPO}/resolve/main/${HF_FILE}"
  echo "Using curl (resumable)..."
  curl -fL -C - --progress-bar -o "$TARGET.part" "$URL"
  mv "$TARGET.part" "$TARGET"
fi

echo ""
echo "✓ Downloaded: $TARGET"
echo "Start server with: $SCRIPT_DIR/start_model.sh $1"
