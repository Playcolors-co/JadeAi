#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <hf-model-path> [output-dir]" >&2
  exit 1
fi

MODEL_PATH="$1"
OUTPUT_DIR="${2:-./models/gguf}"

mkdir -p "$OUTPUT_DIR"

echo "[stub] Converting $MODEL_PATH to GGUF into $OUTPUT_DIR"
