# S3 — Voice Dictation

Proves Merlin's voice dictation captures the microphone, transcribes accurately, and that
the transcribed text drives the agent correctly. Per the user's decision this is **both**
a dedicated scenario (below) **and** woven cues — every other scenario's runsheet has a
step instructing the tester to *speak* a prompt instead of typing it.

**Prerequisite:** task 302 (Info.plist Speech + microphone usage strings) must be
merged, and macOS Speech-recognition + microphone permissions granted to Merlin.

This scenario is **manual** — a human must speak. There is no automated harness hook.

---

## What it proves
- The Speech-recognition and microphone permission prompts appear (post task 302) and,
  once granted, dictation works.
- Transcription is accurate enough across: short commands, long multi-sentence prompts,
  and technical content (code identifiers, file paths, symbols) — the hard case.
- The transcribed text is delivered as a real user message and Merlin acts on it.

---

## Test items

| ID | Spoken input | Expectation |
|----|--------------|-------------|
| D1 | "List the files in the current project." | Transcribed verbatim; Merlin lists files. |
| D2 | A 3-sentence task: *"Open the task board fixture. Add a task called Buy milk. Then tell me how many tasks are done."* | Full multi-sentence transcription; Merlin performs all three steps. |
| D3 | Technical: *"Open ContentView dot swift and find the function add task." * | Identifiers transcribed plausibly (`ContentView.swift`, `addTask`); if mangled, Merlin still resolves intent or asks. |
| D4 | A correction mid-dictation: speak, pause, resume. | Transcription stitches the segments without dropping words. |
| D5 | First-ever dictation on a fresh install | macOS shows the Speech + microphone permission dialogs with Merlin's usage strings. |

---

## Scoring rubric

- [ ] D5 — both permission prompts appear with Merlin's descriptions; granting them
      enables dictation; denying them fails gracefully (no crash — verifies task 302).
- [ ] D1–D4 — transcription word-error rate is low enough that intent is preserved;
      record the transcript verbatim next to what was spoken.
- [ ] Merlin acts on each dictated command correctly.
- [ ] Woven cues: confirm the "speak the prompt" step in S1/S2/S4 runsheets also works.
- [ ] No crash or hang on mic start/stop.

**Score:** items passed / 5, plus a transcription-accuracy note per item.

---

## Runsheet

1. Confirm task 302 is merged and Merlin is freshly built. On first dictation, expect
   the macOS permission dialogs (D5) — grant them.
2. Open any project in Merlin.
3. For D1–D4: press the mic button (or the dictation shortcut), speak the input exactly,
   stop, and **record the transcribed text verbatim** before sending.
4. Send each transcribed prompt; observe whether Merlin does the right thing.
5. Re-run D5 path on a machine/user where permission was never granted (or reset via
   `tccutil reset SpeechRecognition com.merlin.app` and `tccutil reset Microphone
   com.merlin.app`) to confirm the prompts fire.
6. Score against the rubric; write `merlin-eval/results/S3-<date>.md`, including the
   spoken-vs-transcribed pairs.
7. A crash, hang, or denied-permission failure is a finding — record it.
