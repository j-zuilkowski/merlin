# Merlin Performance Optimization Roadmap

## Parallelism (highest upside)

### Parallel worker execution
Run independent sub-tasks concurrently across slots. Currently `stepsPerTurn=1`, `batchSize=1` is maximally conservative. The supervisor would need a dependency graph to identify which worker tasks are safe to parallelize (e.g. editing file A and file B simultaneously).

### Async tool calls
Within a single worker turn, dispatch tools that don't depend on each other in parallel (e.g. read file X + read file Y) and join results before the next generation step.

---

## Local inference (llama.cpp router mode preferred)

### Speculative decoding
Pair qwen3.6-27b with a small draft model (e.g. qwen 0.6b). The draft generates candidate tokens; the main model verifies them in one forward pass. Can yield 2–4× throughput on tasks with predictable output.

### Chunked prefill
For long prompts (post-compaction context), llama.cpp's chunked prefill processes the prompt in batches, keeping the GPU saturated. Prefer running through Merlin's llama.cpp router-mode provider at `localhost:8081` so the text and vision models share one managed local runtime.

### Flash Attention / GPU layer count
Confirm all model layers are offloaded to GPU and Flash Attention is enabled. Easy wins if currently misconfigured.

---

## Context management

### Predictive compaction
Compaction currently triggers reactively at loop start when `estimatedTokens > 10,000`. A rolling token estimate during the loop could compact earlier, before hitting the ceiling mid-task.

### Tiered compaction
Use light summarization for recent turns and aggressive pruning for older turns, rather than a single compaction strategy. Preserves recent reasoning fidelity while freeing space from older history.

### Stable prefix isolation
Separate the immutable system prompt (instructions, preloaded project files) from the mutable conversation history. llama.cpp's prefix cache always hits on the static portion, eliminating redundant prefill work across turns. Pairs well with CAG-style file preloading.

---

## Remote providers

### Prompt caching
For Anthropic-backed slots, mark system prompt sections with cache-control breakpoints. DeepSeek has similar prefix caching. Cuts TTFT and cost significantly on repeated calls with the same system prompt.

### Request coalescing
If the supervisor fires multiple short remote calls in sequence, batch them where the API supports it to reduce round-trip overhead.

---

## Supervisor intelligence

### Worker result memoization
Cache worker outputs keyed on `(task hash, context hash)`. Long loops that revisit the same files get instant replay instead of re-generating.

### Critic gating
Only invoke the critic layer when worker output exceeds a confidence threshold or touches high-risk areas (schema changes, auth code, etc.). Skipping unnecessary critic passes reduces latency per iteration.

### Planner reuse
If a continuation run's task is structurally identical to the prior plan, reuse the existing plan rather than re-planning from scratch.

---

## Priority recommendations

| Priority | Item | Effort | Impact |
|---|---|---|---|
| 1 | Parallel worker execution | High | Very high |
| 2 | Stable prefix isolation | Low | High |
| 3 | Speculative decoding | Medium | High |
| 4 | Predictive compaction | Medium | Medium |
| 5 | Critic gating | Low | Medium |
| 6 | Worker result memoization | Medium | Medium |
| 7 | Prompt caching (remote) | Low | Medium |
| 8 | Tiered compaction | Medium | Medium |
| 9 | Async tool calls | Medium | Medium |
| 10 | Chunked prefill / Flash Attention | Low | Low–Medium |
| 11 | Request coalescing | Low | Low |
