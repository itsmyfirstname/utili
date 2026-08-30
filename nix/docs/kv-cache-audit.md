# KV Cache Quantization — Audit and Recommendations

## What the KV Cache Does

The KV cache stores Key and Value tensors for each attention layer. The server reuses these tensors during generation. A larger context requires a larger KV cache.

---

## Current Configuration

```
--cache-type-k q4_0
--cache-type-v q4_0
```

Both K and V caches use 4-bit quantization. This is aggressive. It saves VRAM but reduces generation quality.

> **Reference:** [llama.cpp KV cache quantization](https://github.com/ggml-org/llama.cpp/blob/master/docs/kv-cache-quantization.md)

---

## Why K and V Are Different

The Key cache is more sensitive to quantization than the Value cache. Reducing K precision degrades attention quality more than reducing V precision.

This asymmetry is documented in research:

> **Reference:** [KIVI: Asymmetric KV cache quantization](https://arxiv.org/abs/2402.02750)

---

## Available Quantization Types (llama.cpp)

| Type | Bits | VRAM Cost | Quality |
|---|---|---|---|
| `f16` | 16 | Highest | Best |
| `q8_0` | 8 | High | Very good |
| `q5_0` | 5 | Medium | Good |
| `q4_1` | 4 | Low-medium | Good |
| `q4_0` | 4 | Low | Fair |

> **Reference:** [llama.cpp server README — cache-type flags](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)

---

## VRAM Impact at 131,072 Context

KV cache VRAM scales linearly with context length. At 131k tokens, the difference between `q4_0` and `q8_0` is approximately **2.5–3.0 GB**.

| K type | V type | Est. KV VRAM (131k ctx) | Notes |
|---|---|---|---|
| `q4_0` | `q4_0` | ~5.3 GB | Current — aggressive |
| `q8_0` | `q4_0` | ~7.0 GB | Recommended — better K precision |
| `q8_0` | `q8_0` | ~8.8 GB | Full quality — requires context reduction |
| `f16` | `f16` | ~17.5 GB | Not feasible at 131k context |

---

## Recommendation

Set K to `q8_0`. Leave V at `q4_0`. This improves attention quality with a modest VRAM increase.

### Current (line 159 of `llamacpp.nix`)

```nix
ExecStart = "... --cache-type-k q4_0 --cache-type-v q4_0 ...";
```

### Proposed Change

```nix
ExecStart = "... --cache-type-k q8_0 --cache-type-v q4_0 ...";
```

This uses approximately **1.7 GB more VRAM** at max context. You have ~5.6 GB of free headroom. The change is safe.

---

## If You Reduce Context

If you reduce context to `65536`, KV cache VRAM drops by half. This makes `q8_0` on both K and V feasible.

```nix
ExecStart = "... -c 65536 --cache-type-k q8_0 --cache-type-v q8_0 ...";
```

This gives the best KV cache quality while freeing VRAM for a larger model quantization (Q5).

---

## Flash Attention Requirement

You already have `-fa on`. Flash attention is required for KV cache quantization to work correctly in llama.cpp. Do not remove it.

> **Reference:** [llama.cpp performance tips](https://github.com/ggml-org/llama.cpp/blob/master/docs/development/token-generation-performance-tips.md)
