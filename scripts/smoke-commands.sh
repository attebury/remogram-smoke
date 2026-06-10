#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .remogram.json ]]; then
  echo "Copy a config example to .remogram.json first (see config/)." >&2
  exit 1
fi

run() {
  echo "==> remogram $*"
  remogram "$@" --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ok') is not False, d; print('ok', d.get('type'))"
}

run doctor
run provider capabilities
run repo status
run refs compare --base main --head feature/smoke-1
run pr view --number 1
run pr checks --number 1
run merge plan --number 1

echo "Smoke battery passed."
