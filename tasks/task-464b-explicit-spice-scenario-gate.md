# Task 464b - Explicit SPICE Scenario Gate

## Implementation

`kicad_generate_spice_scenario` no longer fabricates a generic SPICE deck from
`project_path` alone. It now requires:

- `project_path`
- `circuit_ir_path` with `verification_scenarios` containing `kind = spice`
- `spice_scenario_path` / `simulation_scenario_path` pointing to a
  `SPICESimulationScenario` JSON artifact
- scenario `circuit_path` pointing to an existing runnable SPICE deck
- at least one analysis
- explicit required model references
- explicit pass/fail measurement envelopes

When valid, the runtime copies the referenced deck to the workflow output and
returns it as the `simulation_scenario` artifact. The explicit scenario JSON is
also returned as `spice_scenario` evidence.

## AmpDemo Evidence

The live AmpDemo SPICE slice now creates an explicit scenario JSON, invokes
`kicad_generate_spice_scenario`, and then invokes `kicad_run_spice` with the
generated deck and the required `output_power_w` envelope.

Latest artifacts:

- Source deck: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/3A85AE41-D6CB-4BB4-8A14-F9AEF8301308/amp_low_voltage_audio_smoke.cir`
- Generated deck: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/3A85AE41-D6CB-4BB4-8A14-F9AEF8301308/amp_low_voltage_audio-amp-output-power-scenario.cir`
- Scenario JSON: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/3A85AE41-D6CB-4BB4-8A14-F9AEF8301308/amp_low_voltage_audio_spice_scenario.json`
- ngspice log: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/44573533-AEC0-41A9-9D0F-17DC68F50AEB-spice.log`

Measured result:

- `output_power_w = 1.52331`

Required envelope:

- `24.0...28.0 W`

Conclusion: Merlin now blocks the AmpDemo SPICE gate from explicit scenario
evidence instead of allowing a generic generated smoke deck to falsely advance
the workflow.

