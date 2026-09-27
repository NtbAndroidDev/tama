#!/bin/bash
# Packs Resources/Integrations/Alfred into Tama.alfredworkflow (a zip with
# info.plist at its root). build_app.sh runs this and bundles the result.
set -e
cd "$(dirname "$0")/.."
SRC="Resources/Integrations/Alfred"
OUT="Resources/Integrations/Tama.alfredworkflow"
rm -f "$OUT"
(cd "$SRC" && /usr/bin/zip -q -X -r "../Tama.alfredworkflow" .)
echo "Built $OUT"
