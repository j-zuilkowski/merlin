# S4 Fixture Build — rag-corpus

Builds the S4 fixture: a tiny knowledge corpus of **invented, unguessable facts** so a
correct answer can only come from retrieval, never from model priors.

## Layout
`merlin-eval/fixtures/rag-corpus/` — two EPUBs, ingested into a running xcalibre-server
during the S4 run:
- `glimworks-manual.epub`
- `glimworks-history.epub`

## Corpus content (the planted facts — keep verbatim)

**glimworks-manual** — title "Glimworks Mark IV — Operator Manual", body:
> The Glimworks Mark IV operates at a pressure of 47 kilopascals. Its calibration cycle
> takes 19 minutes to complete. To reset the unit, enter the reset code TANGERINE-7 on
> the front panel.

**glimworks-history** — title "A Short History of Glimworks Industries", body:
> Glimworks Industries was founded in the city of Vorren in the year 1888. Its founder
> was the engineer Ada Pellington, who built the first Glimworks workshop by hand.

Scoring facts: 47 kPa · 19 minutes · TANGERINE-7 · Vorren · 1888 · Ada Pellington.
S4 question 4 ("maximum rotational speed") is **deliberately absent** — do not add it.

## Build recipe

A minimal EPUB is a zip with `mimetype` stored first (uncompressed). Write this script
to `merlin-eval/fixtures/rag-corpus/make-epub.sh` and run it twice.

```bash
#!/usr/bin/env bash
# make-epub.sh <slug> <title> <bodyfile>
set -euo pipefail
slug="$1"; title="$2"; bodyfile="$3"
work="$(mktemp -d)"
mkdir -p "$work/META-INF" "$work/OEBPS"
printf 'application/epub+zip' > "$work/mimetype"
cat > "$work/META-INF/container.xml" <<'XML'
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
XML
cat > "$work/OEBPS/text.xhtml" <<XHTML
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>${title}</title></head>
<body><h1>${title}</h1><p>$(cat "$bodyfile")</p></body></html>
XHTML
cat > "$work/OEBPS/content.opf" <<OPF
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">merlin-eval-${slug}</dc:identifier>
    <dc:title>${title}</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest><item id="t" href="text.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="t"/></spine>
</package>
OPF
out="$(pwd)/${slug}.epub"
rm -f "$out"
( cd "$work" && zip -X0 "$out" mimetype >/dev/null && zip -Xr9D "$out" META-INF OEBPS >/dev/null )
rm -rf "$work"
echo "wrote $out"
```

Run it:
```bash
cd merlin-eval/fixtures/rag-corpus
chmod +x make-epub.sh
printf 'The Glimworks Mark IV operates at a pressure of 47 kilopascals. Its calibration cycle takes 19 minutes to complete. To reset the unit, enter the reset code TANGERINE-7 on the front panel.' > /tmp/gw-manual.txt
printf 'Glimworks Industries was founded in the city of Vorren in the year 1888. Its founder was the engineer Ada Pellington, who built the first Glimworks workshop by hand.' > /tmp/gw-history.txt
./make-epub.sh glimworks-manual  "Glimworks Mark IV — Operator Manual"      /tmp/gw-manual.txt
./make-epub.sh glimworks-history "A Short History of Glimworks Industries" /tmp/gw-history.txt
```

## Verify
```bash
cd merlin-eval/fixtures/rag-corpus
for f in glimworks-manual.epub glimworks-history.epub; do
  unzip -l "$f" | grep -qE 'mimetype' && echo "$f OK" || echo "$f BAD"
done
```
Expected: both files exist and are valid EPUB zips (`mimetype` present). They are
ingested into xcalibre-server per the S4 runsheet; if the server rejects this minimal
EPUB, fall back to the server's documented accepted format and record it in `BLOCKED.md`.
