# Overthinking Mitigation — Qwen3 Thinking Tokens

## The Problem

Qwen3 models use a thinking mode. In this mode, the model generates internal reasoning tokens before the final answer. These tokens are called "thinking tokens."

Thinking tokens increase latency. They increase time-to-first-token. They increase total generation time. They consume context window space.

Long completions and slow responses are often caused by unconstrained thinking.

---

## How Qwen3 Thinking Works

Qwen3 supports two modes:

| Mode | Behavior |
|---|---|
| Thinking ON | Model reasons before answering. Slower. More accurate on hard tasks. |
| Thinking OFF | Model answers directly. Faster. Good for most tasks. |

The model switches modes based on the system prompt or a special token.

> **Reference:** [Qwen3 model documentation — thinking mode](https://qwen.readthedocs.io/en/latest/deployment/vllm.html)
> **Reference:** [Qwen3 GitHub — thinking control](https://github.com/QwenLM/Qwen3)

---

## Method 1: Disable Thinking in the System Prompt

Add `/no_think` to the system prompt. The model reads this instruction and skips the thinking phase.

**Example system prompt:**

```
/no_think
You are a helpful assistant.
```

This is the simplest method. It works without changing the server config.

> **Reference:** [Qwen3 thinking mode toggle](https://huggingface.co/Qwen/Qwen3-30B-A3B#switching-between-thinking-and-non-thinking-mode)

---

## Method 2: Set a Token Budget

Use `--thinking-budget` to limit the number of thinking tokens. This does not disable thinking. It caps the depth of reasoning.

Set a low value for simple tasks. Set a higher value for complex coding or math.

```nix
ExecStart = "${llama-cpp-cuda}/bin/llama-server \
  ... \
  --thinking-budget 1024";
```

A value of `0` disables thinking entirely in supported builds.

> **Reference:** [llama.cpp server flags](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)

---

## Method 3: Use Chat Template Control (Jinja)

Your current config uses `--jinja`. This enables the model's built-in chat template.

The Qwen3 template supports `enable_thinking: false` as a generation parameter. Pass this in the API request body.

**API request example:**

```json
{
  "model": "Qwen3",
  "messages": [...],
  "chat_template_kwargs": {
    "enable_thinking": false
  }
}
```

This disables thinking on a per-request basis. You do not need to change the server config.

> **Reference:** [Qwen3 chat template — enable_thinking parameter](https://huggingface.co/Qwen/Qwen3-30B-A3B#processing-long-texts)

---

## Recommendation

Use Method 3 for maximum flexibility. Set `enable_thinking: false` in the API request for all routine tasks. Use `enable_thinking: true` only for complex multi-step reasoning.

This reduces latency. It reduces VRAM pressure. It frees context window space for actual conversation.
