# Tokens Per Second — Speed Optimization

## Current State

| Metric | Value |
|---|---|
| GPU | RTX 3090 24 GB |
| GPU Utilization | 98% |
| Power Draw | 347W / 350W |
| Batch size | 2048 |
| Ubatch size | 512 |
| Context | 131,072 tokens |

The GPU is at near-maximum compute and power. Simple flag changes will not double throughput. The bottleneck is the model size relative to the GPU.

---

## What Controls Tokens Per Second

Token generation speed depends on:

1. **Memory bandwidth** — how fast the GPU reads model weights per token
2. **Batch size** — how many tokens the GPU processes in parallel
3. **Context length** — longer context = more KV cache reads per token
4. **Model size** — larger models = more weight reads per token

The RTX 3090 has 936 GB/s memory bandwidth. This is the hard ceiling.

> **Reference:** [RTX 3090 specs — TechPowerUp](https://www.techpowerup.com/gpu-specs/geforce-rtx-3090.c3622)

---

## Optimization 1: Reduce Context Window

**Impact: High**

131,072 tokens of context is very large. Each generated token attends to all prior tokens. This is expensive. Reducing context to 32,768 or 65,536 increases throughput measurably.

```nix
# Reduce from 131072 to 65536
ExecStart = "... -c 65536 ...";
```

Most sessions do not use 131k tokens. Set context to the largest value your actual sessions require.

> **Reference:** [llama.cpp context length and performance](https://github.com/ggml-org/llama.cpp/blob/master/docs/development/token-generation-performance-tips.md)

---

## Optimization 2: Tune Ubatch Size

**Impact: Medium**

The `-ub` flag controls physical batch size per GPU kernel call. A larger ubatch increases throughput for prompt processing. A smaller ubatch reduces latency for single-token generation.

Try `512` (current) vs `256` vs `1024`. Use `nvidia-smi dmon` to measure GPU utilization while generating.

```nix
# Try smaller for single-user, lower-latency use
ExecStart = "... -ub 256 ...";

# Try larger for batch/parallel request use
ExecStart = "... -ub 1024 ...";
```

> **Reference:** [llama.cpp batch parameters](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md#common-params)

---

## Optimization 3: Speculative Decoding

**Impact: High — if you have a compatible draft model**

Speculative decoding uses a small draft model to generate candidate tokens. The large model verifies them in parallel. This can increase throughput by 2–3x.

You need a small Qwen3 draft model (1.7B or 4B) on GPU simultaneously. This requires free VRAM.

```nix
ExecStart = "${llama-cpp-cuda}/bin/llama-server \
  -m /var/lib/models/Qwen3.8-27B-Q4_0.gguf \
  --draft-model /var/lib/models/Qwen3-1.7B-Q8_0.gguf \
  -ngld 99 \
  ...";
```

You have ~5.6 GB free. Qwen3-1.7B at Q8_0 is approximately 1.9 GB. This fits.

> **Reference:** [llama.cpp speculative decoding](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md#speculative-decoding)
> **Reference:** [Qwen3-1.7B on Hugging Face](https://huggingface.co/Qwen/Qwen3-1.7B)

---

## Optimization 4: Disable Thinking Mode

**Impact: High — for latency and effective TPS**

Thinking tokens count against generation time but do not appear in the final output. Disabling thinking mode reduces time-to-completion significantly.

See `overthinking-mitigation.md` for full details.

---

## What Will NOT Help

| Action | Reason |
|---|---|
| Increasing batch size beyond 2048 | GPU is already at 98% utilization |
| Enabling more CPU offload | PCIe bandwidth is far slower than VRAM bandwidth |
| Overclocking GPU memory | RTX 3090 consumer cards do not support memory OC safely |

---

## Realistic Throughput Targets

| Change | Expected TPS Gain |
|---|---|
| Reduce context to 65k | +15–25% |
| Disable thinking mode | +30–60% effective (fewer output tokens) |
| Add speculative decoding (1.7B draft) | +50–150% if acceptance rate is high |
| Upgrade to RTX 4090 | +40% (more bandwidth, same VRAM) |

