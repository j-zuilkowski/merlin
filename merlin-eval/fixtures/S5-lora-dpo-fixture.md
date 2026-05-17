# S5 Fixture Build — lora-dpo

Builds the S5 fixture: ~40 DPO preference pairs that seed Merlin's LoRA training queue.
**Pipeline-integrity test** — content quality is irrelevant, schema validity is not.

## Layout
`merlin-eval/fixtures/lora-dpo/pending/` — 40 pair files. The S5 runsheet copies them to
`~/.merlin/lora/pending/` (after backing up any real one).

## Schema (confirmed from `Merlin/Engine/DPOQueue.swift` — `DPOPendingEntry`)
One JSON file per pair, named `<id>.json`, at `~/.merlin/lora/pending/`:
```json
{
  "id": "<uuid>",
  "prompt": "<the user message>",
  "chosen": "<preferred response>",
  "rejected": "<original response>",
  "model_id": "<provider model id>",
  "timestamp": "<ISO-8601, e.g. 2026-05-17T12:00:00Z>"
}
```
(`JSONDecoder` with `.iso8601` dates; key `model_id` is snake_case — the rest match.)

The seeded preference is trivial and consistent: **"answer in one sentence"** —
`chosen` is a single sentence, `rejected` is a verbose multi-sentence answer to the same
prompt.

## Build recipe

Write to `merlin-eval/fixtures/lora-dpo/generate.sh` and run it:
```bash
#!/usr/bin/env bash
# Emits 40 schema-valid DPO pairs into ./pending/.
set -euo pipefail
out="$(dirname "$0")/pending"
mkdir -p "$out"
ts="2026-05-17T12:00:00Z"
model="qwen/qwen3.6-27b"
topics=(gravity photosynthesis tides erosion fermentation magnetism \
        evaporation inflation osmosis combustion)
i=0
for t in "${topics[@]}"; do
  for variant in a b c d; do
    i=$((i+1))
    id="$(uuidgen)"
    prompt="Explain ${t} (variant ${variant})."
    # plain interpolation only — macOS system bash is 3.2 and lacks the
    # ${var^} case-modification operator (bash 4+); do not reintroduce it.
    chosen="The topic ${t} is a natural process explained in one clear sentence."
    rejected="Well, ${t} is quite interesting. There are many aspects to it. First, one must consider the background. Then there is the mechanism. Finally, the effects are worth discussing at length."
    cat > "$out/${id}.json" <<JSON
{
  "id" : "${id}",
  "prompt" : "${prompt}",
  "chosen" : "${chosen}",
  "rejected" : "${rejected}",
  "model_id" : "${model}",
  "timestamp" : "${ts}"
}
JSON
  done
done
echo "wrote ${i} DPO pairs to ${out}"
```
Run:
```bash
cd merlin-eval/fixtures/lora-dpo && chmod +x generate.sh && ./generate.sh
```
That writes 40 pairs (10 topics × 4 variants).

## Training config
Per S5, the run is triggered through **Settings → LoRA** (`LoRASettingsSection`), not a
config file — the tiny iteration count (`iters ≈ 20`, small batch, small `lora_layers`)
is set in that UI during the S5 runsheet. If the trainer also reads a `train-config.json`
(confirm against `Merlin/Engine/LoRATrainer.swift`), seed this minimal one beside the
pairs as `merlin-eval/fixtures/lora-dpo/train-config.json`:
```json
{ "iters": 20, "batch_size": 1, "lora_layers": 4 }
```
Reconcile the key names with `LoRATrainer.swift` before the run; a mismatch is a finding.

## Verify
```bash
cd merlin-eval/fixtures/lora-dpo
ls pending/*.json | wc -l            # expect 40
python3 -c "import json,glob; [json.load(open(f)) for f in glob.glob('pending/*.json')]; print('all 40 parse')"
python3 -c "import json; d=json.load(open(__import__('glob').glob('pending/*.json')[0])); assert set(d)=={'id','prompt','chosen','rejected','model_id','timestamp'}; print('schema OK')"
```
Expected: 40 files, all valid JSON, each with exactly the 6 schema keys.
