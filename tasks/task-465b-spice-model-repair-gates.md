# Task 465b - SPICE Model Evidence And Repair Gates

## Implementation

`kicad_generate_spice_scenario` now requires a local SPICE model records
artifact before it can produce runnable simulation evidence. The handler
decodes the records, resolves every `required_model_refs` entry in the explicit
scenario, blocks missing or unusable models, and returns the model records path
as a `spice_model_records` artifact when generation succeeds.

`kicad_repair_spice_from_diagnostics` now treats the repair loop as bounded
engineering work instead of an open-ended retry. It blocks when no repair is
needed, and it also blocks when proposed patch parameters do not have declared
min/max bounds in `repair_parameters` or `spice_parameters`.

## AmpDemo Evidence

The live AmpDemo SPICE slice now uses a representative low-voltage Class-A
output-stage deck instead of the previous smoke deck. The scenario explicitly
excludes off-board mains/transformer behavior and validates the output-stage
power envelope only.

Latest artifacts:

- Source deck: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/BD078EDD-477A-40D4-8867-9AA5B10F8DD6/amp_low_voltage_audio_output_stage.cir`
- Generated deck: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/BD078EDD-477A-40D4-8867-9AA5B10F8DD6/amp_low_voltage_audio-amp-output-power-scenario.cir`
- Scenario JSON: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/BD078EDD-477A-40D4-8867-9AA5B10F8DD6/amp_low_voltage_audio_spice_scenario.json`
- Model records: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/BD078EDD-477A-40D4-8867-9AA5B10F8DD6/amp_low_voltage_audio_spice_models.json`
- ngspice log: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/6ACE10FE-AEB4-4576-9877-ACC0D6D1857B-spice.log`

Measured result:

- `output_power_w = 26.9563`

Required envelope:

- `24.0...28.0 W`

Conclusion: this is a real explicit output-stage simulation gate for the
focused AmpDemo SPICE slice. It is not a claim that the full amplifier, mains
board, thermal design, schematic, PCB, BOM, ERC, or DRC are complete.

