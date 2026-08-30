# Model Comparison Matrix — Q4_K_M vs Q5_K_M (+ Draft)

## Purpose

This document compares two real deployment paths using files from `JonathanColetti/Qwen3.8-27B-Uncensored-GGUF` on the RTX 3090 (24,576 MiB VRAM).

---

## 1. Candidate Configurations

### Configuration A — "Speed & Throughput" (Q4_K_M + Dedicated Draft)
- **Base model:** `Qwen3.8-27B-Uncensored-Q4_K_M.gguf` (~16.2 GB)
- **Draft model:** `Qwen3.8-27B-Uncensored-draft-Q4_0.gguf` (~1.1 GB)
- **Context:** 65,536 (extendable to 96,000)
- **KV Cache:** `k=q8_0`, `v=q4_0`
- **Thinking:** ON

### Configuration B — "Maximum Precision / Red Liner" (Q5_K_M Standalone)
- **Base model:** `Qwen3.8-27B-Uncensored-Q5_K_M.gguf` (~19.5 GB)
- **Draft model:** None
- **Context:** 65,536 (strict ceiling)
- **KV Cache:** `k=q8_0`, `v=q4_0`
- **Thinking:** ON

---

## 2. VRAM Allocation Breakdown (RTX 3090 24GB)

| Component | Config A (Q4_K_M + Draft @ 65k) | Config A (Q4_K_M + Draft @ 96k) | Config B (Q5_K_M @ 65k) |
|---|---|---|---|
| **Base Model Weights** | 16,200 MiB | 16,200 MiB | 19,500 MiB |
| **Draft Model Weights** | 1,100 MiB | 1,100 MiB | 0 MiB |
| **KV Cache (k=q8_0, v=q4_0)** | 3,560 MiB | 5,260 MiB | 3,560 MiB |
| **Draft KV / Overhead** | 200 MiB | 250 MiB | 0 MiB |
| **Display / CUDA Runtime** | 100 MiB | 100 MiB | 100 MiB |
| **Total VRAM Consumption** | **21,160 MiB** | **22,910 MiB** | **23,160 MiB** |
| **Safety Headroom** | **✅ 3,416 MiB** | **✅ 1,666 MiB** | **⚠️ 1,416 MiB** |

---

## 3. Comparison Across Optimization Dimensions

| Metric / Goal | Current Baseline (Q4_0, 131k ctx, q4/q4 KV) | Config A (Q4_K_M + Draft, 65k-96k ctx, q8/q4 KV) | Config B (Q5_K_M, 65k ctx, q8/q4 KV) |
|---|---|---|---|
| **Weight Precision** | 4.0 bits (uniform) | 4.5 bits (k-quant + imatrix) | 5.5 bits (k-quant + imatrix) |
| **KV Attention Quality** | Low (q4_0 on K) | High (q8_0 on K) | High (q8_0 on K) |
| **Context Window** | 131,072 | 65,536 – 96,000 | 65,536 |
| **Thinking Tokens Latency** | High (sequential single-model generation) | **Low to Medium** (draft accelerates token generation) | High (heavier weights to stream per token) |
| **Estimated Throughput (TPS)** | Baseline (1.0x) | **1.6x – 2.4x** | **0.85x – 0.90x** |
| **OOM Risk** | Zero (~5.6 GB free) | Very Low (3.4 GB free @ 65k) | Low (1.4 GB free @ 65k) |

---

## 4. Analysis and Findings

### Why Config A (Q4_K_M + Draft) Solves Long Computation Time & Overthinking
1. **Dedicated Draft Advantage:** The `Qwen3.8-27B-Uncensored-draft-Q4_0.gguf` file is custom-built for this exact base model. Token acceptance rates are significantly higher than generic draft models.
2. **Accelerates Thinking:** When thinking mode is active, the draft generates intermediate reasoning tokens rapidly. The base model verifies multiple tokens in parallel per step.
3. **Improves Over Baseline:** `Q4_K_M` with importance matrix (`imatrix`) has measurably lower perplexity loss than raw `Q4_0`, while `k=q8_0` protects attention precision.

### Why Config B (Q5_K_M) is Strict Quality
1. **Upper Bound Quality:** `Q5_K_M` retains ~99% of FP16 reasoning accuracy.
2. **Throughput Cost:** Without a draft model, every token requires reading the full ~19.5 GB from GPU memory.
3. **Context Bound:** At 65k context, you cannot safely push to 100k without risking CUDA out-of-memory errors during large prompt evaluations.

---

## 5. Nix Service Declarations

### Option 1: Apply Config A (Speed & Throughput)
```nix
ExecStart = "${llama-cpp-cuda}/bin/llama-server \
  -m /var/lib/models/Qwen3.8-27B-Uncensored-Q4_K_M.gguf \
  --draft-model /var/lib/models/Qwen3.8-27B-Uncensored-draft-Q4_0.gguf \
  --models-dir /var/lib/models --no-models-autoload --jinja \
  --host 0.0.0.0 --port 9000 \
  -ngl 999 -ngld 99 \
  -c 65536 \
  --cache-type-k q8_0 --cache-type-v q4_0 \
  -fa on -b 2048 -ub 512";
```

### Option 2: Apply Config B (Maximum Precision)
```nix
ExecStart = "${llama-cpp-cuda}/bin/llama-server \
  -m /var/lib/models/Qwen3.8-27B-Uncensored-Q5_K_M.gguf \
  --models-dir /var/lib/models --no-models-autoload --jinja \
  --host 0.0.0.0 --port 9000 \
  -ngl 999 \
  -c 65536 \
  --cache-type-k q8_0 --cache-type-v q4_0 \
  -fa on -b 2048 -ub 512";
```
