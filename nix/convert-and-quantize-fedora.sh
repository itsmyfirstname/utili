#!/usr/bin/env bash
# Usage: ./convert-and-quantize-fedora.sh <HF_MODEL_ID> <QUANT_TYPE> <OUTPUT_NAME>
# Example: ./convert-and-quantize-fedora.sh Qwen/Qwen3-1.7B Q8_0 Qwen3-1.7B-Draft

set -euo pipefail

MODEL_ID="${1:-Qwen/Qwen3-1.7B}"
TARGET_QUANT="${2:-Q8_0}"
OUT_NAME="${3:-Qwen3-1.7B}"
WORKDIR="${WORKDIR:-./workspace}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

echo "=== 1. Checking Fedora Dependencies ==="
# Ensure git, cmake, gcc-c++, and uv / python are present
MISSING_PKGS=()
for cmd in git cmake g++ uv; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING_PKGS+=("$cmd")
  fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
  echo "Missing required tools: ${MISSING_PKGS[*]}"
  echo "On Fedora, run: sudo dnf install -y git cmake gcc-c++ python3-pip && pip install uv"
  exit 1
fi

# Convert WORKDIR and OUTPUT_DIR to absolute paths
mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT_DIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

echo "=== 2. Building llama-quantize from source ==="
cd "$WORKDIR"
if [ ! -d "llama.cpp" ]; then
  git clone --depth 1 https://github.com/ggml-org/llama.cpp.git
fi

if [ ! -f "llama.cpp/build/bin/llama-quantize" ]; then
  cmake -B llama.cpp/build -S llama.cpp -DGGML_CUDA=OFF
  cmake --build llama.cpp/build --config Release --target llama-quantize -j"$(nproc)"
fi
QUANTIZE_BIN="$WORKDIR/llama.cpp/build/bin/llama-quantize"

echo "=== 3. Downloading $MODEL_ID from Hugging Face ==="
rm -rf "$WORKDIR/source"
mkdir -p "$WORKDIR/source"

# Download the full repo into source directory
hf download "$MODEL_ID" --local-dir "$WORKDIR/source"

# Verify config.json exists
if [ ! -f "$WORKDIR/source/config.json" ]; then
  echo "Error: config.json not found in $WORKDIR/source. Checking subdirectories..."
  NESTED_CONFIG=$(find "$WORKDIR/source" -name "config.json" | head -n 1)
  if [ -n "$NESTED_CONFIG" ]; then
    SRC_DIR="$(dirname "$NESTED_CONFIG")"
  else
    echo "Fatal: Could not locate config.json in downloaded files."
    exit 1
  fi
else
  SRC_DIR="$WORKDIR/source"
fi

echo "=== 4. Converting Safetensors to BF16 GGUF ==="
uv run \
  --with torch \
  --with transformers \
  --with sentencepiece \
  --with protobuf \
  "$WORKDIR/llama.cpp/convert_hf_to_gguf.py" "$SRC_DIR" \
  --outtype bf16 \
  --outfile "$WORKDIR/${OUT_NAME}-BF16.gguf"

echo "=== 5. Quantizing to $TARGET_QUANT ==="
"$QUANTIZE_BIN" "$WORKDIR/${OUT_NAME}-BF16.gguf" "$OUTPUT_DIR/${OUT_NAME}-${TARGET_QUANT}.gguf" "$TARGET_QUANT"

echo "=== 6. Cleaning Up Intermediate Files ==="
rm -rf "$WORKDIR/source" "$WORKDIR/${OUT_NAME}-BF16.gguf"

echo "=== Finished! Created: $OUTPUT_DIR/${OUT_NAME}-${TARGET_QUANT}.gguf ==="
