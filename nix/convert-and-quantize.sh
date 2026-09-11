#!/usr/bin/env bash
# Usage: ./convert-and-quantize.sh <HF_MODEL_ID> <QUANT_TYPE> <OUTPUT_NAME>
# Example: ./convert-and-quantize.sh Qwen/Qwen3-1.7B Q8_0 Qwen3-1.7B-Draft

set -euo pipefail

MODEL_ID="${1:-Qwen/Qwen3-1.7B}"
TARGET_QUANT="${2:-Q5_K_M}"
OUT_NAME="${3:-Qwen3-1.7B}"
WORKDIR="/mnt/models/workspace"
DESTDIR="/mnt/models/qwen38"

echo "=== 1. Preparing Workspace ($WORKDIR) ==="
mkdir -p "$WORKDIR"
mkdir -p "$DESTDIR"
cd "$WORKDIR"

if [ ! -f "convert_hf_to_gguf.py" ]; then
  echo "Downloading convert_hf_to_gguf.py..."
  curl -sLO https://raw.githubusercontent.com/ggml-org/llama.cpp/master/convert_hf_to_gguf.py
fi

echo "=== 2. Downloading $MODEL_ID via hf ==="
rm -rf "$WORKDIR/source"
hf download "$MODEL_ID" --local-dir "$WORKDIR/source" --exclude "*.bin" "*.pth" "*.msgpack"

echo "=== 3. Converting to BF16 GGUF ==="
uv run \
  --with torch \
  --with transformers \
  --with sentencepiece \
  --with protobuf \
  convert_hf_to_gguf.py "$WORKDIR/source" \
  --outtype bf16 \
  --outfile "$WORKDIR/${OUT_NAME}-BF16.gguf"

echo "=== 4. Quantizing to $TARGET_QUANT ==="
QUANTIZE_BIN=$(find /nix/store -name "llama-quantize" 2>/dev/null | grep cuda | head -1)
if [ -z "$QUANTIZE_BIN" ]; then
  QUANTIZE_BIN=$(find /nix/store -name "llama-quantize" 2>/dev/null | head -1)
fi

echo "Using quantizer binary: $QUANTIZE_BIN"
"$QUANTIZE_BIN" "$WORKDIR/${OUT_NAME}-BF16.gguf" "$DESTDIR/${OUT_NAME}-${TARGET_QUANT}.gguf" "$TARGET_QUANT"

echo "=== 5. Cleaning Intermediate Files ==="
rm -rf "$WORKDIR/source" "$WORKDIR/${OUT_NAME}-BF16.gguf"

echo "=== Finished! Created $DESTDIR/${OUT_NAME}-${TARGET_QUANT}.gguf ==="
