#!/usr/bin/env bash
# Run remogram-mcp tools for the forge in .remogram.json; write packets to RUN_DIR/<slug>/mcp/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_DIR="${1:-}"
if [[ -z "$RUN_DIR" ]]; then
  echo "usage: capture-forge-mcp-smoke.sh <run-dir>" >&2
  exit 1
fi

if [[ ! -f .remogram.json ]]; then
  echo "Missing .remogram.json — copy from config/*.example" >&2
  exit 1
fi

PROVIDER="$(python3 -c "import json; print(json.load(open('.remogram.json'))['provider'])")"
FORGE_SLUG="${FORGE_SLUG:-$PROVIDER}"
REMOTE="$(python3 -c "import json; print(json.load(open('.remogram.json')).get('remote','origin'))")"
OUT="$RUN_DIR/$FORGE_SLUG/mcp"
mkdir -p "$OUT"

REMOGRAM_ROOT="${REMOGRAM_ROOT:-$HOME/Documents/remogram}"
CAPTURE="$REMOGRAM_ROOT/packages/remogram-mcp/capture-tools.mjs"
if [[ ! -f "$CAPTURE" ]]; then
  echo "Missing $CAPTURE — set REMOGRAM_ROOT to remogram checkout" >&2
  exit 1
fi

echo "MCP capture $FORGE_SLUG -> $OUT"
REMOGRAM_CWD="$ROOT" node "$CAPTURE" "$OUT" --remote "$REMOTE" || true

python3 - <<PY
import json, pathlib
meta = {
  "forge_slug": "$FORGE_SLUG",
  "provider": "$PROVIDER",
  "transport": "stdio",
  "remogram_config": json.load(open(".remogram.json")),
}
pathlib.Path("$OUT/meta.json").write_text(json.dumps(meta, indent=2) + "\n")
PY

echo "Captured MCP $FORGE_SLUG -> $OUT"
