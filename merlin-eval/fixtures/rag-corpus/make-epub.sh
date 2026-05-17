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
