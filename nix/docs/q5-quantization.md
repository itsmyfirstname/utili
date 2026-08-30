# Q5 Quantization — Feasibility Analysis

## What Q5 Means

A quantization level sets the number of bits used to store each model weight.

- **Q4_0** = 4 bits per weight (current)
- **Q5_K_M** = 5.5 bits per weight (recommended Q5 target)
- **Q5_0** = 5 bits per weight (simpler, less accurate)

Higher bit depth = better output quality, more VRAM required.

> **Reference:** [llama.cpp quantization types](https://github.com/ggml-org/llama.cpp/wiki/Feature-matrix)

---

## Current VRAM Budget

| Item | Size |
|------|------|
| Total VRAM | 24,576 MiB |
| Used by llama-server | 18,850 MiB |
| Used by display (GNOME + Xwayland) | ~62 MiB |
| **Free headroom** | **~5,664 MiB** |

---

## Weight Size by Quantization

The model is `Qwen3.8-27B`. This is a Mixture-of-Experts (MoE) architecture. It has approximately 27B total parameters.

| Quantization | Bits/Weight | Approx. Weight Size |
|---|---|---|
| Q4_0 (current) | 4.0 | ~13.5 GB |
| Q5_0 | 5.0 | ~16.9 GB |
| Q5_K_M | 5.5 | ~18.6 GB |
| Q8_0 | 8.0 | ~27.0 GB |

> **Reference:** [GGUF quantization format — Hugging Face docs](https://huggingface.co/docs/hub/en/gguf)

---

## KV Cache Overhead

At 131,072 tokens of context, the KV cache consumes significant VRAM even when quantized to Q4_0.

The current setup uses approximately **5.3 GB** for the KV cache at max context. This is the delta between weight size (~13.5 GB) and total VRAM used (~18.85 GB).

---

## Verdict: Q5_0 Is Feasible. Q5_K_M Is Not — At Full Context.

| Option | Weight Size | KV Cache | Total Est. | Fits in 24 GB? |
|---|---|---|---|---|
| Q4_0 (current) | ~13.5 GB | ~5.3 GB | ~18.8 GB | ✅ Yes |
| Q5_0 | ~16.9 GB | ~5.3 GB | ~22.2 GB | ✅ Yes (tight) |
| Q5_K_M | ~18.6 GB | ~5.3 GB | ~23.9 GB | ⚠️ Borderline |
| Q5_K_M + reduced ctx | ~18.6 GB | ~2.0 GB | ~20.6 GB | ✅ Yes |

### To Use Q5_0

Replace the model path in `llamacpp.nix`:

```nix
ExecStart = "${llama-cpp-cuda}/bin/llama-server \
  -m /var/lib/models/Qwen3.8-27B-Q5_0.gguf \
  ...";
```

You must download or requantize the model to Q5_0 first.

> **Requantize with llama.cpp:** [llama-quantize tool](https://github.com/ggml-org/llama.cpp/blob/master/examples/quantize/README.md)

### To Use Q5_K_M

Reduce context window to 65,536 or lower to free VRAM for the larger weights:

```nix
ExecStart = "${llama-cpp-cuda}/bin/llama-server \
  -m /var/lib/models/Qwen3.8-27B-Q5_K_M.gguf \
  -c 65536 \
  ...";
```

---

## Quality Gain

Q5_K_M improves perplexity over Q4_0 by approximately 5–8%. This is measurable on coding and reasoning tasks. The gain is smaller on conversational tasks.

> **Reference:** [llama.cpp quantization benchmarks](https://github.com/ggml-org/llama.cpp/pull/1684)

---

## Recommendation

1. Download `Qwen3.8-27B-Q5_K_M.gguf` from Hugging Face.
2. Set context to `65536`.
3. Keep KV cache at `q4_0` to recover VRAM.
4. Monitor VRAM with `nvidia-smi -l 1` after restart.

This gives better output quality with a safe VRAM margin.
