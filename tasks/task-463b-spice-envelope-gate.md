# Task 463b - SPICE Envelope Gate

## Implementation

`kicad_run_spice` now accepts generic `measurement_envelopes` /
`measurementEnvelopes` / `required_measurements` / `requiredMeasurements`
payload entries. After ngspice exits successfully, Merlin parses the generated
measurement log and evaluates the requested envelopes.

If any required measurement is missing or outside range, Merlin returns
`BLOCKED_SIMULATION`, preserves the `spice_measurements` artifact, and routes
the next action to SPICE repair/rerun instead of falsely completing the step.

The ngspice parser now reads scalar values from real output lines that include
trailing metadata, such as:

```text
vout_rms = 3.49091e+00 from= 1.00000e-02 to= 2.00000e-02
```

## AmpDemo Evidence

The live AmpDemo SPICE slice was rerun with a local sentinel:

```sh
touch /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-spice-slice
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testAmpDemoSPICESliceBlocksWhen25WEnvelopeFails
rm -f /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-spice-slice
```

Result: `TEST SUCCEEDED`.

Produced artifacts:

- Deck: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/3C6F8825-3FF8-4CD8-93A1-B8CE5F4B45F1/amp_low_voltage_audio_smoke.cir`
- Log: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/2BAFA3E2-B834-45DF-A9E7-894DED762D6B-spice.log`

Measured output: `output_power_w = 1.52331`.

Expected envelope: `24.0...28.0 W`.

Conclusion: the current AmpDemo SPICE smoke deck is valid simulator evidence
but not 25 W amplifier performance evidence, so Merlin correctly blocks the
SPICE gate.

