# LLM Configuration

## Provider Overview

| Provider | Endpoint | Auth | Use Case |
|---|---|---|---|
| DeepSeek V4 Pro | `https://api.deepseek.com/v1` | API key | Reasoning, long context, code, tool calls |
| DeepSeek V4 Flash | `https://api.deepseek.com/v1` | API key | Fast agentic loops, cheap tool iteration |
| LM Studio (local) | `http://localhost:1234/v1` | None | Vision tasks, offline, privacy |

---

## DeepSeek V4 Models

### deepseek-v4-pro

| Property | Value |
|---|---|
| Total parameters | 1.6T |
| Active parameters per token | 49B (MoE) |
| Context window | 1,000,000 tokens |
| Max output | 384,000 tokens |
| Architecture | Hybrid Attention (CSA + HCA) |
| Thinking mode | Yes (`"thinking": {"type": "enabled"}`) |
| Vision / multimodal | No (in development) |
| API format | OpenAI ChatCompletions + Anthropic |
| Model ID | `deepseek-v4-pro` |

**When to use:** Complex reasoning, architecture decisions, debugging sessions, long file context, anything requiring sustained multi-step thinking. Enable thinking mode for non-trivial tasks.

### deepseek-v4-flash

| Property | Value |
|---|---|
| Total parameters | 284B |
| Active parameters per token | 13B (MoE) |
| Context window | 1,000,000 tokens |
| Max output | 384,000 tokens |
| Thinking mode | Yes |
| Vision / multimodal | No |
| Model ID | `deepseek-v4-flash` |

**When to use:** High-frequency agentic tool calls, read/write file loops, shell command execution, any task where speed matters more than deep reasoning. Default for mechanical operations.

### Deprecation Notice

`deepseek-chat` and `deepseek-reasoner` are retired after **July 24, 2026**. Use `deepseek-v4-pro` and `deepseek-v4-flash` exclusively.

### API Request Example (with thinking)

```json
{
  "model": "deepseek-v4-pro",
  "messages": [...],
  "thinking": { "type": "enabled" },
  "reasoning_effort": "high",
  "tools": [...],
  "stream": true
}
```

---

## Local Vision Model (LM Studio)

### Qwen2.5-VL-72B-Instruct — Primary Vision Model

| Property | Value |
|---|---|
| Parameters | 72B |
| Quantization (recommended) | Q4_K_M (GGUF) |
| Download size | 47.4 GB |
| RAM at Q4_K_M | ~47 GB |
| Remaining RAM (128GB system) | ~81 GB free |
| Speed on M4 Mac Studio 128GB | ~15–20 tok/s |
| Context window | 32,768 tokens (native) |
| Vision input | Yes — images as base64 in message content |
| LM Studio catalog name | `Qwen2.5-VL-72B-Instruct-Q4_K_M.gguf` |
| HuggingFace repo | `lmstudio-community/Qwen2.5-VL-72B-Instruct-GGUF` (bartowski build) |
| Provider | bartowski (LM Studio-sponsored, llama.cpp b5317) |

**Capability benchmarks:**

| Benchmark | Score |
|---|---|
| ScreenSpot (UI element localization) | 87.1% |
| ScreenSpot Pro | 43.6% |
| Android Control High Precision | 67.4% |
| Android Control Low Precision | 93.7% |

**When to use:** Any GUI interaction task where the macOS Accessibility tree is absent or shallow — Electron apps, custom-drawn UIs, web views, game UIs. Receives JPEG screenshots from ScreenCaptureKit and returns element coordinates or semantic descriptions.

### Qwen3-VL-30B-A3B — Speed Fallback Vision Model

| Property | Value |
|---|---|
| Total parameters | 30B |
| Active parameters per token | 3B (MoE) |
| Quantization (recommended) | Q4_K_M (GGUF) or MLX 4-bit |
| RAM at Q4 | ~20 GB |
| Speed on M4 Mac Studio (MLX 4-bit) | 100+ tok/s |
| Thinking mode | Yes |
| Vision input | Yes |

**When to use:** If 72B proves too slow for tight agentic iteration loops. Accuracy on screen tasks is lower than 72B but MoE architecture makes it dramatically faster. Use thinking mode for ambiguous UI states.

---

## LM Studio Setup — Qwen2.5-VL-72B

### Download

1. Open LM Studio
2. Search: `qwen2.5-vl-72b`
3. Select: `Qwen2.5-VL-72B-Instruct-Q4_K_M.gguf`
4. Download (~43 GB)

### Load Parameters

| Parameter | Value | Notes |
|---|---|---|
| Context Length | `8192` | Vision tasks don't need large context; saves RAM |
| GPU Layers | `-1` (all) | Full Metal offload to Apple Silicon GPU |
| CPU Threads | `8` | Leave headroom for OS and other tools |
| Flash Attention | `on` | Required for performance on long vision inputs |
| Keep Model in RAM | `on` | Avoid reload latency between agent calls |
| Seed | `-1` (random) | |
| Rope Frequency Base | `1000000` | Default for Qwen2.5 architecture |

### Server Settings (Local API)

| Setting | Value |
|---|---|
| Server port | `1234` |
| CORS | Enabled |
| Verbose logging | Off (reduces noise) |
| Max concurrent requests | `1` (single-user local) |

### Image Handling Parameters

```json
{
  "min_pixels": 200704,
  "max_pixels": 1003520
}
```

`min_pixels = 256 × 28 × 28` and `max_pixels = 1280 × 28 × 28`. Keep `max_pixels` conservative to avoid RAM spikes when processing large screenshots. For a standard 1440p display screenshot, this is well within limits.

### API Call Shape (vision, from Swift)

```
POST http://localhost:1234/v1/chat/completions
Content-Type: application/json

{
  "model": "Qwen2.5-VL-72B-Instruct-Q4_K_M",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,<base64-encoded-screenshot>"
          }
        },
        {
          "type": "text",
          "text": "Identify the location of the 'Build' button. Return JSON: {\"x\": <int>, \"y\": <int>, \"confidence\": <float>}"
        }
      ]
    }
  ],
  "max_tokens": 256,
  "temperature": 0.1
}
```

Use `temperature: 0.1` for coordinate/action responses — you want deterministic output, not creativity.

---

## Runtime Model Selection Logic

```
Task type?
├── Reasoning / architecture / debugging    → deepseek-v4-pro (thinking: enabled)
├── File ops / shell / fast tool loop       → deepseek-v4-flash
└── GUI screenshot analysis
    ├── AX tree available and rich?         → skip vision model entirely
    ├── Standard screen task                → Qwen2.5-VL-72B (primary)
    └── Tight loop / speed critical         → Qwen3-VL-30B-A3B (fallback)
```

---

## Screenshot Optimization for Vision Model

To minimize RAM usage and maximize model accuracy on macOS screenshots:

- Capture at **logical resolution** (not retina 2x) via ScreenCaptureKit — reduces pixel count 4x with no meaningful information loss for UI element detection
- Encode as **JPEG at quality 85** — good detail, ~2–4x smaller than PNG
- Crop to the **active window** rather than full screen when possible
- Target image size: under 1MB before base64 encoding

---

## Hardware Reference

**M4 Mac Studio 128GB**

| Property | Value |
|---|---|
| Unified memory | 128 GB |
| Memory bandwidth | ~546 GB/s (M4 Max) |
| Recommended inference backend | MLX (15–30% faster than GGUF at same quantization) |
| LM Studio MLX support | Yes (enable in settings) |

For maximum vision model throughput, prefer MLX quantized variants in LM Studio over GGUF when available for the selected model.
