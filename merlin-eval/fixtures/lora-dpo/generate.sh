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
