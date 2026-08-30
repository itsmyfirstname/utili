# Fine-Tuning Qwen — Feasibility on RTX 3090

## The Goal

Fine-tune the Qwen model to improve performance on a specific task or dataset.

---

## VRAM Requirements for Fine-Tuning

Fine-tuning requires more VRAM than inference. The GPU must hold:

- Model weights
- Gradient tensors (same size as weights)
- Optimizer state (2x weights for Adam)
- Activation checkpoints
- Batch data

This is 4–8x more VRAM than inference alone.

| Model Size | Inference VRAM | Full Fine-Tune VRAM | QLoRA VRAM |
|---|---|---|---|
| 7B | ~6 GB | ~56 GB | ~10–14 GB |
| 14B | ~10 GB | ~112 GB | ~18–24 GB |
| 27B | ~14 GB | ~216 GB | ~30–40 GB |

> **Reference:** [Hugging Face — model memory calculator](https://huggingface.co/spaces/hf-accelerate/model-memory-usage)

---

## Can You Fine-Tune Qwen3.8-27B on a 3090?

**No. Not in a useful configuration.**

The 27B model requires 30–40 GB of VRAM for QLoRA fine-tuning. The RTX 3090 has 24 GB. This is not enough.

---

## What You Can Fine-Tune on a 3090

You can fine-tune smaller Qwen models on a single 3090.

| Model | QLoRA VRAM | Feasible? |
|---|---|---|
| Qwen3-0.6B | ~3 GB | ✅ Yes |
| Qwen3-1.7B | ~5 GB | ✅ Yes |
| Qwen3-4B | ~9 GB | ✅ Yes |
| Qwen3-8B | ~16 GB | ✅ Yes |
| Qwen3-14B | ~22 GB | ✅ Tight — batch size 1, gradient checkpointing required |
| Qwen3-32B | ~38 GB | ❌ No |

> **Reference:** [Qwen3 model sizes on Hugging Face](https://huggingface.co/collections/Qwen/qwen3-67d4d5f7d5f7f7f7f7f7f7f7)

---

## Recommended Tool: Unsloth

Unsloth is a fine-tuning library. It reduces VRAM usage by 50–70% compared to standard QLoRA. It supports Qwen3 natively.

> **Reference:** [Unsloth — GitHub](https://github.com/unslothai/unsloth)
> **Reference:** [Unsloth — Qwen3 fine-tuning notebook](https://colab.research.google.com/drive/1aQLNONMk9tsTv9PCjXqbkH7GJvFkOHaG)

---

## How to Fine-Tune Qwen3-8B with Unsloth

### Step 1: Install Unsloth

```bash
pip install unsloth
```

> **Reference:** [Unsloth installation](https://github.com/unslothai/unsloth?tab=readme-ov-file#-installation-instructions)

### Step 2: Load the Model

```python
from unsloth import FastLanguageModel

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name = "Qwen/Qwen3-8B",
    max_seq_length = 4096,
    load_in_4bit = True,  # QLoRA
)
```

### Step 3: Apply LoRA Adapters

```python
model = FastLanguageModel.get_peft_model(
    model,
    r = 16,                 # LoRA rank
    target_modules = ["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha = 16,
    lora_dropout = 0.05,
    bias = "none",
)
```

### Step 4: Train

Use the Hugging Face `Trainer` or `SFTTrainer` from `trl`.

> **Reference:** [TRL SFTTrainer documentation](https://huggingface.co/docs/trl/en/sft_trainer)

---

## Output Format

Fine-tuning produces LoRA adapter weights. You merge them with the base model. You export the result to GGUF format for use with llama.cpp.

```bash
# Export to GGUF after merging
python convert_hf_to_gguf.py ./merged-model --outtype q5_k_m
```

> **Reference:** [llama.cpp convert_hf_to_gguf](https://github.com/ggml-org/llama.cpp/blob/master/convert_hf_to_gguf.py)

---

## Recommended Path

1. Choose a dataset for your target task.
2. Fine-tune **Qwen3-8B** using Unsloth on the 3090.
3. Export to GGUF at Q5_K_M.
4. Deploy the fine-tuned model on your existing llama.cpp server.
5. Compare output quality against the 27B base model.

A fine-tuned 8B model on a specific task often outperforms a generic 27B model on that task.

> **Reference:** [Fine-tuning vs. large models — scaling laws overview](https://arxiv.org/abs/2001.08361)
