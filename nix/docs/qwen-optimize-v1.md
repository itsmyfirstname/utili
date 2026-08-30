## Realistic Throughput Targets

| Change | Expected TPS Gain |
|---|---|
| Reduce context to 65k | +15–25% |
| Add speculative decoding (1.7B draft) | +50–150% if acceptance rate is high |


## VRAM Impact at 131,072 Context

KV cache VRAM scales linearly with context length. At 131k tokens, the difference between `q4_0` and `q8_0` is approximately **2.5–3.0 GB**.

| K type | V type | Est. KV VRAM (131k ctx) | Notes |
|---|---|---|---|
| `q4_0` | `q4_0` | ~5.3 GB | Current — aggressive |
| `q8_0` | `q4_0` | ~7.0 GB | Recommended — better K precision |
| `q8_0` | `q8_0` | ~8.8 GB | Full quality — requires context reduction |

### Recommendation

Set K to `q8_0`. Leave V at `q4_0`. This improves attention quality with a modest VRAM increase.



---

# Path Assessment — Two Proposed Configurations

## Baseline: What the Numbers Say

These values are derived from the current nvidia-smi snapshot.

| Item | Value |
|---|---|
| Total VRAM | 24,576 MiB |
| Display overhead | ~62 MiB |
| Available to llama-server | ~24,514 MiB |
| Current llama-server usage (131k ctx, Q4_0, q4_0 KV) | 18,850 MiB |
| Implied model weights (Q4_0, 27B) | ~13,800 MiB |
| Implied KV cache at 131k ctx, q4_0/q4_0 | ~4,750 MiB |
| KV cache at 65k ctx (half of above) | ~2,375 MiB |
| KV cache at 65k, k=q8_0, v=q4_0 | ~3,560 MiB |
| KV cache at 100k, k=q8_0, v=q4_0 | ~5,478 MiB |
| Q5_K_M weights (5.5 bits × 27B) | ~18,600 MiB |
| Q5_0 weights (5.0 bits × 27B) | ~16,900 MiB |
| Qwen3-1.7B draft at Q8_0 | ~1,740 MiB |
| Draft KV overhead | ~200 MiB |

> **Note:** KV cache size scales linearly with context length and with bits-per-element. Doubling context doubles KV usage. Upgrading K from q4_0 to q8_0 doubles the K portion only.

---

## Path 1 — Balanced Load With Speculative Decoding

**Goal:** Maximize throughput using speculative decoding. Keep thinking ON. Context between 65k and 100k.

### VRAM Budget at Each Context Target

| Sub-config | Weights | KV Cache | Draft | Display | Total | Headroom |
|---|---|---|---|---|---|---|
| Q5_0 + 65k ctx + spec | 16,900 | 3,560 | 1,940 | 62 | **22,462** | ✅ ~2,052 MiB |
| Q5_0 + 100k ctx + spec | 16,900 | 5,478 | 1,940 | 62 | **24,380** | ⚠️ ~134 MiB |
| Q5_K_M + 65k ctx + spec | 18,600 | 3,560 | 1,940 | 62 | **24,162** | ⚠️ ~352 MiB |
| Q5_K_M + 100k ctx + spec | 18,600 | 5,478 | 1,940 | 62 | **26,080** | ❌ exceeds by 1,566 MiB |

### Assessment

Q5_K_M at 100k with speculative decoding does not fit. Do not attempt it.

Q5_0 at 65k is the only sub-config with a safe headroom margin. Use this as the starting point.

Q5_K_M at 65k with speculative decoding is borderline. The ~352 MiB headroom is too narrow. Transient VRAM spikes during batch processing can exceed this margin. The server will crash.

**Thinking ON adds indirect pressure.** Each thinking session generates 2,000–15,000 tokens before the reply. Those tokens occupy the KV cache. At 65k context with a 5,000-token thinking burst, the effective user context drops to ~60k. This does not change VRAM allocation. llama.cpp pre-allocates the full KV cache at startup. Thinking ON does not cause OOM. It does reduce usable context per session.

**Speculative decoding acceptance rate with thinking ON is uncertain.** The 1.7B draft model must generate thinking-style tokens that the 27B main model accepts. For structured reasoning, acceptance rates may be lower than for direct responses. Expect 40–65% acceptance on thinking tokens vs. 65–80% on direct response tokens.

**Recommended Path 1 config:**

```
Model: Q5_0
Context: 65,536
KV: k=q8_0, v=q4_0
Spec decoding: Qwen3-1.7B at Q8_0
Thinking: ON
```

Expand to 100k context only after you verify the Q5_0 + spec decoding combo is stable at 65k. At 100k the margin is ~134 MiB — acceptable only if no other GPU processes are running.

---

## Path 2 — Red Liner (Maximum Model Quality)

**Goal:** Run the highest quality model config the hardware can sustain. No speculative decoding. Thinking ON. Context 65k.

### VRAM Budget

| Item | MiB |
|---|---|
| Q5_K_M weights | 18,600 |
| KV at 65k, k=q8_0, v=q4_0 | 3,560 |
| Display overhead | 62 |
| Buffer / overhead | ~300 |
| **Total** | **~22,522** |
| **Headroom** | **~1,992 MiB** |

### Assessment

Path 2 is comfortable. Nearly 2 GB of headroom at the stated config. The 3090 will not OOM under normal load.

This path trades throughput for quality. You get the best possible output from the weights. You give up the TPS multiplier from speculative decoding.

**Quality gain over current config:**
- Q5_K_M over Q4_0: approximately 5–8% perplexity improvement. This is measurable on coding, math, and multi-step reasoning tasks.
- K cache at q8_0 over q4_0: reduces attention drift on long contexts. The improvement is most visible past 20k tokens of context. At short sessions, the difference is small.

**Thinking ON at 65k context:** The model has room to think. A 10k-token thinking budget leaves 55k for conversation history. This is sufficient for most sessions.

**TPS on Path 2:** Expect lower tokens-per-second than Path 1. The larger Q5_K_M weights require more memory bandwidth per token. The RTX 3090 has 936 GB/s. Larger weights = more time to stream weights per forward pass. Rough estimate: Q5_K_M will generate tokens approximately 15–20% slower than Q4_0 at the same context.

---

## Comparison Table

| Attribute | Path 1 (Balanced) | Path 2 (Red Liner) |
|---|---|---|
| Model quant | Q5_0 | Q5_K_M |
| KV cache | k=q8_0, v=q4_0 | k=q8_0, v=q4_0 |
| Context | 65,536 (extendable to 100k) | 65,536 |
| Thinking | ON | ON |
| Speculative decoding | Qwen3-1.7B Q8_0 | No |
| VRAM headroom | ~2,052 MiB | ~1,992 MiB |
| Output quality | Good | Best |
| Throughput | Higher (spec decoding gain) | Lower |
| Stability risk | Low at 65k, borderline at 100k | Low |

---

## Recommendation

**Start with Path 2.** It requires no additional model download. It establishes a quality baseline. It is stable.

After running Path 2 for a session or two, check whether TPS is acceptable for your workflow. If TPS is the bottleneck, switch to Path 1 with Q5_0 and the 1.7B draft at 65k context.

Do not run Q5_K_M and speculative decoding simultaneously. The combined VRAM cost exceeds the hardware budget unless context is fixed at 65k and you accept less than 400 MiB of headroom.

**If you want the absolute best single-response quality, run Path 2.**
**If you want faster iteration and are willing to accept slightly lower weight precision, run Path 1 at 65k.**

---

## Proposed `llamacpp.nix` Entries

### Path 1 — Balanced

```nix
ExecStart = "${llama-cpp-cuda}/bin/llama-server \
  -m /var/lib/models/Qwen3.8-27B-Q5_0.gguf \
  --draft-model /var/lib/models/Qwen3-1.7B-Q8_0.gguf \
  --models-dir /var/lib/models --no-models-autoload --jinja \
  --host 0.0.0.0 --port 9000 \
  -ngl 999 -ngld 99 \
  -c 65536 \
  --cache-type-k q8_0 --cache-type-v q4_0 \
  -fa on -b 2048 -ub 512";
```

### Path 2 — Red Liner

```nix
ExecStart = "${llama-cpp-cuda}/bin/llama-server \
  -m /var/lib/models/Qwen3.8-27B-Q5_K_M.gguf \
  --models-dir /var/lib/models --no-models-autoload --jinja \
  --host 0.0.0.0 --port 9000 \
  -ngl 999 \
  -c 65536 \
  --cache-type-k q8_0 --cache-type-v q4_0 \
  -fa on -b 2048 -ub 512";
```

> **Model files needed:**
> - Path 1: [Qwen3-27B Q5_0 on Hugging Face](https://huggingface.co/models?search=qwen3+27b+Q5_0) + [Qwen3-1.7B on Hugging Face](https://huggingface.co/Qwen/Qwen3-1.7B)
> - Path 2: [Qwen3-27B Q5_K_M on Hugging Face](https://huggingface.co/models?search=qwen3+27b+Q5_K_M)

---

# Concrete Model Evaluation: Q4_K_M (+ Draft) vs Q5_K_M

Using files from [`JonathanColetti/Qwen3.8-27B-Uncensored-GGUF`](https://huggingface.co/JonathanColetti/Qwen3.8-27B-Uncensored-GGUF):

| Metric | Config A: Q4_K_M + Dedicated Draft | Config B: Q5_K_M Standalone |
|---|---|---|
| **Base Model** | `Qwen3.8-27B-Uncensored-Q4_K_M.gguf` (~16.2 GB) | `Qwen3.8-27B-Uncensored-Q5_K_M.gguf` (~19.5 GB) |
| **Draft Model** | `Qwen3.8-27B-Uncensored-draft-Q4_0.gguf` (~1.1 GB) | None |
| **KV Cache** | `k=q8_0`, `v=q4_0` | `k=q8_0`, `v=q4_0` |
| **Working Context** | 65,536 (headroom allows up to 96k) | 65,536 (hard limit) |
| **Total VRAM @ 65k** | **~21.16 GB** (~3.4 GB free) | **~23.16 GB** (~1.4 GB free) |
| **Throughput (TPS)** | **High (1.6x – 2.4x baseline)** | **Low (0.85x – 0.90x baseline)** |
| **Thinking Latency** | **Fast** (draft model verifies tokens in parallel) | **Slow** (heavy forward passes per token) |
| **Output Quality** | High (imatrix-calibrated K-quant) | Maximum (~99% FP16 fidelity) |

### Direct Recommendation
- If your primary pain points are **long computation times** and **overthinking delays**, deploy **Config A (Q4_K_M + Draft)**. It gives a major TPS speedup while upgrading your current Q4_0 precision and fixing KV attention degradation.
- If you need **absolute maximum reasoning fidelity** and do not mind slower generation, deploy **Config B (Q5_K_M)**.
