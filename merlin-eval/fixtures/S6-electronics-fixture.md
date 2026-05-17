# S6 Fixture Build — electronics

S6 has two parts. **Part A** (555 astable design) needs no pre-built fixture — Merlin
creates the board from scratch; the "fixture" is just an empty working directory.
**Part B** (schematic OCR) needs a known schematic image + a ground-truth netlist.

## Part A — working directory
Merlin writes the `.kicad_sch` / `.kicad_pcb` / ngspice files into this directory:
```bash
mkdir -p merlin-eval/fixtures/electronics
```
No fixture *content* for Part A — the 555 astable spec lives in the S6 scenario prompt.
Do **not** `rm -rf` this directory: the Part B OCR fixture lives inside it at
`electronics/schematic-image/`, and the harness (`testS6Electronics`) only ensures the
directory exists — it never wipes it. Always run Part A before Part B.

## Part B — schematic OCR fixture
Location: `merlin-eval/fixtures/electronics/schematic-image/`
- `rc-filter.png` — a clear raster image of the schematic below
- `ground-truth.json` — the scoring reference

### The known schematic — an RC low-pass filter
Deliberately simple and unambiguous (2 components, 3 nets):
- **R1** — 10 kΩ resistor, between net `VIN` (pin 1) and net `OUT` (pin 2)
- **C1** — 100 nF capacitor, between net `OUT` (pin 1) and net `GND` (pin 2)
- `VIN` is the input; `OUT` is the filter output; `GND` is ground.

### `ground-truth.json` (write verbatim)
```json
{
  "schematic": "RC low-pass filter",
  "components": [
    { "designator": "R1", "value": "10k",   "type": "resistor" },
    { "designator": "C1", "value": "100nF", "type": "capacitor" }
  ],
  "nets": [
    { "name": "VIN", "pins": ["R1-1"] },
    { "name": "OUT", "pins": ["R1-2", "C1-1"] },
    { "name": "GND", "pins": ["C1-2"] }
  ]
}
```

### Producing `rc-filter.png`
Build the schematic above in KiCad, then export to PNG:
1. KiCad → new schematic; place `R` (set value `10k`, reference `R1`) and `C` (value
   `100nF`, reference `C1`); wire `R1` pin 1 to a labelled net `VIN`, `R1` pin 2 +
   `C1` pin 1 to a labelled net `OUT`, `C1` pin 2 to `GND` (a ground symbol).
2. Export to PDF, then rasterise to PNG. `sips` (macOS-native) reads PDF but **cannot
   read SVG** — so go via PDF, not SVG:
   `kicad-cli sch export pdf --output rc-filter.pdf rc-filter.kicad_sch`
   `sips -s format png --resampleHeightWidthMax 2000 rc-filter.pdf --out rc-filter.png`
   (If librsvg is installed, `kicad-cli sch export svg` + `rsvg-convert rc-filter.svg -o
   rc-filter.png` also works — but never run `sips` on an `.svg`; it fails to render it.)
3. Confirm `rc-filter.png` is a legible raster image; keep `rc-filter.kicad_sch` beside
   it for provenance.

The image must be clear enough for vision OCR — high contrast, components and net
labels readable. If `kicad-cli` PDF/SVG export is unavailable, plot from the KiCad GUI
(File → Plot → SVG/PDF) and rasterise. A blurry or low-DPI image is a fixture defect,
not a Merlin finding.

## Verify
```bash
ls merlin-eval/fixtures/electronics                       # exists; holds schematic-image/ (Part B)
cd merlin-eval/fixtures/electronics/schematic-image
file rc-filter.png | grep -q 'PNG image' && echo "image OK"
python3 -c "import json; d=json.load(open('ground-truth.json')); assert len(d['components'])==2 and len(d['nets'])==3; print('ground-truth OK')"
```
Expected: the working dir exists (containing the `schematic-image/` subdir);
`rc-filter.png` is a valid PNG; `ground-truth.json` parses with 2 components and 3 nets.
