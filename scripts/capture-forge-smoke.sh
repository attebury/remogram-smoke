#!/usr/bin/env bash
# Run remogram smoke battery for the forge in .remogram.json; write JSON packets to RUN_DIR.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_DIR="${1:-}"
if [[ -z "$RUN_DIR" ]]; then
  echo "usage: capture-forge-smoke.sh <run-dir>" >&2
  exit 1
fi

if [[ ! -f .remogram.json ]]; then
  echo "Missing .remogram.json — copy from config/*.example" >&2
  exit 1
fi

PROVIDER="$(python3 -c "import json; print(json.load(open('.remogram.json'))['provider'])")"
FORGE_SLUG="${FORGE_SLUG:-$PROVIDER}"
OUT="$RUN_DIR/$FORGE_SLUG"
mkdir -p "$OUT"

capture() {
  local file=$1
  shift
  local stderr_file="$OUT/${file%.json}.stderr"
  local exit_code=0
  remogram "$@" --json >"$OUT/$file" 2>"$stderr_file" || exit_code=$?
  if [[ ! -s $OUT/$file ]]; then
    printf '{"ok":false,"type":"capture_error","exit_code":%s,"command_file":"%s"}\n' "$exit_code" "$file" >"$OUT/$file"
  fi
  echo "$file exit=$exit_code"
  return 0
}

capture doctor.json doctor
capture provider_capabilities.json provider capabilities
capture repo_status.json repo status
capture refs_compare.json refs compare --base main --head feature/smoke-1
capture pr_view.json pr view --number 1
capture pr_checks.json pr checks --number 1
capture merge_plan.json merge plan --number 1

python3 - <<PY
import json, pathlib
meta = {
  "forge_slug": "$FORGE_SLUG",
  "provider": "$PROVIDER",
  "remogram_config": json.load(open(".remogram.json")),
  "git_main": "$(git rev-parse main 2>/dev/null || echo null)",
  "git_feature_smoke_1": "$(git rev-parse feature/smoke-1 2>/dev/null || echo null)",
}
pathlib.Path("$OUT/meta.json").write_text(json.dumps(meta, indent=2) + "\n")
PY

echo "Captured $FORGE_SLUG ($PROVIDER) -> $OUT"
