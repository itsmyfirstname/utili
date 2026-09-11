# Model Conversion and Quantization Pipeline

## 1. Overview

This document describes the end-to-end pipeline to convert Hugging Face models to GGUF and quantize them with importance matrix (`imatrix`) calibration.

```
+--------------------------+
|  Hugging Face Safetensors |
+--------------------------+
             |
             v  (Step 1: convert_hf_to_gguf.py)
+--------------------------+
|       F16 / BF16 GGUF    |
+--------------------------+
             |
             v  (Step 2: llama-imatrix -- Optional but Recommended)
+--------------------------+
|   Importance Matrix .dat |
+--------------------------+
             |
             v  (Step 3: llama-quantize)
+--------------------------+
| Target Quant (Q5_K_M/etc)|
+--------------------------+
```

---

## 2. Prerequisites and Environment Setup

You can execute all Python steps using `uv` without polluting system libraries.

```bash
# 1. Install Hugging Face CLI tool
uv tool install "huggingface_hub[cli]"

# 2. Prepare workspace directory on fast local disk or NAS
mkdir -p /mnt/models/workspace
cd /mnt/models/workspace

# 3. Fetch the latest convert_hf_to_gguf script from llama.cpp repository
curl -sLO https://raw.githubusercontent.com/ggml-org/llama.cpp/master/convert_hf_to_gguf.py
```

---

## 3. Step-by-Step Execution Pipeline

### Step 1: Download Source Safetensors from Hugging Face

Download the raw BF16 weights:

```bash
hf download <HF_ORG>/<HF_MODEL_NAME> \
  --local-dir /mnt/models/workspace/source-model \
  --exclude "*.bin" "*.pth" "*.msgpack"
```

*Example for Qwen:*
```bash
hf download Qwen/Qwen3-1.7B \
  --local-dir /mnt/models/workspace/source-model
```

---

### Step 2: Convert Safetensors to Unquantized (F16 / BF16) GGUF

Run the conversion script with required dependencies via `uv`:

```bash
uv run \
  --with torch \
  --with transformers \
  --with sentencepiece \
  --with protobuf \
  convert_hf_to_gguf.py /mnt/models/workspace/source-model \
  --outtype bf16 \
  --outfile /mnt/models/workspace/model-BF16.gguf
```

> **Note on RAM:** BF16 conversion loads tensor shards sequentially. Ensure system RAM is greater than 1.5x the largest tensor shard.

---

### Step 3: Compute Importance Matrix (Optional, High Quality)

An importance matrix (`imatrix`) measures which model weights are most sensitive during inference. Quantizing with an `imatrix` preserves quality on small quants (like Q4_K_M and Q5_K_M).

1. Download standard calibration dataset:
```bash
curl -sLO https://raw.githubusercontent.com/ggml-org/llama.cpp/master/scripts/calibration_datav3.txt
```

2. Locate `llama-imatrix` binary from the Nix store:
```bash
IMATRIX_BIN=$(find /nix/store -name "llama-imatrix" 2>/dev/null | grep cuda | head -1)
```

3. Run calibration:
```bash
$IMATRIX_BIN \
  -m /mnt/models/workspace/model-BF16.gguf \
  -f calibration_datav3.txt \
  -o /mnt/models/workspace/imatrix.dat \
  -ngl 99
```

---

### Step 4: Quantize to Target Precision

Locate `llama-quantize` in the Nix store:

```bash
QUANTIZE_BIN=$(find /nix/store -name "llama-quantize" 2>/dev/null | grep cuda | head -1)
```

#### Option A: Quantize with Importance Matrix (Best Precision)
```bash
$QUANTIZE_BIN \
  --imatrix /mnt/models/workspace/imatrix.dat \
  /mnt/models/workspace/model-BF16.gguf \
  /mnt/models/qwen38/MyModel-Q5_K_M.gguf \
  Q5_K_M
```

#### Option B: Standard Quantize (Fastest)
```bash
$QUANTIZE_BIN \
  /mnt/models/workspace/model-BF16.gguf \
  /mnt/models/qwen38/MyModel-Q5_K_M.gguf \
  Q5_K_M
```

---

## 4. Automated All-in-One Bash Script

Save the following automated script as `convert-and-quantize.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

MODEL_ID="${1:-Qwen/Qwen3-1.7B}"
TARGET_QUANT="${2:-Q5_K_M}"
OUT_NAME="${3:-Qwen3-1.7B}"
WORKDIR="/mnt/models/workspace"

echo "=== 1. Setting up Workspace ==="
mkdir -p "$WORKDIR"
cd "$WORKDIR"
curl -sLO https://raw.githubusercontent.com/ggml-org/llama.cpp/master/convert_hf_to_gguf.py

echo "=== 2. Downloading $MODEL_ID ==="
hf download "$MODEL_ID" --local-dir "$WORKDIR/source"

echo "=== 3. Converting Safetensors to BF16 GGUF ==="
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
"$QUANTIZE_BIN" "$WORKDIR/${OUT_NAME}-BF16.gguf" "/mnt/models/qwen38/${OUT_NAME}-${TARGET_QUANT}.gguf" "$TARGET_QUANT"

echo "=== 5. Cleaning Intermediate Files ==="
rm -rf "$WORKDIR/source" "$WORKDIR/${OUT_NAME}-BF16.gguf"

echo "=== Successfully built: /mnt/models/qwen38/${OUT_NAME}-${TARGET_QUANT}.gguf ==="
```

Make it executable:
```bash
chmod +x convert-and-quantize.sh
```

Run it:
```bash
./convert-and-quantize.sh Qwen/Qwen3-1.7B Q8_0 Qwen3-1.7B-Draft
```
