#!/usr/bin/env bash
# Opt-in live GitHub Tier B write smoke for the remogram-smoke fixture repo.
#
# Mutates forge state (opens then closes a disposable issue). Never run in CI by default.
#
# Prerequisites:
#   - remogram on PATH (beta with github-api Tier B writes)
#   - GITHUB_TOKEN or GH_TOKEN with repo scope on attebury/remogram-smoke
#   - cp config/remogram.github.json.example .remogram.json
#   - cp config/remogram.github-writes.operator.json.example ~/.config/remogram-smoke/github-writes.operator.json
#     (or set REMOGRAM_OPERATOR_CONFIG to your copy)
#
# Usage:
#   export GITHUB_TOKEN=...
#   export REMOGRAM_OPERATOR_CONFIG=$HOME/.config/remogram-smoke/github-writes.operator.json
#   REMOGRAM_SMOKE_GITHUB_WRITES=1 ./scripts/smoke-github-writes.sh
#
# Optional: SMOKE_RUN_DIR=runs/manual-github-writes to capture packets (default: runs/<utc>/github-api-writes)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${REMOGRAM_SMOKE_GITHUB_WRITES:-}" != "1" ]]; then
  echo "Refusing live GitHub writes without REMOGRAM_SMOKE_GITHUB_WRITES=1" >&2
  echo "This script opens a disposable issue, comments, verifies, then closes it." >&2
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN or GH_TOKEN required" >&2
  exit 1
fi
export GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

if [[ -z "${REMOGRAM_OPERATOR_CONFIG:-}" ]]; then
  echo "REMOGRAM_OPERATOR_CONFIG required (see config/remogram.github-writes.operator.json.example)" >&2
  exit 1
fi

if [[ ! -f .remogram.json ]]; then
  cp config/remogram.github.json.example .remogram.json
  echo "Copied config/remogram.github.json.example -> .remogram.json" >&2
fi

PROVIDER="$(python3 -c "import json; print(json.load(open('.remogram.json'))['provider'])")"
if [[ "$PROVIDER" != "github-api" ]]; then
  echo ".remogram.json provider must be github-api (got $PROVIDER)" >&2
  exit 1
fi

RUN_ID="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="${SMOKE_RUN_DIR:-$ROOT/runs/$RUN_ID/github-api-writes}"
mkdir -p "$RUN_DIR"

RUN_TAG="${RUN_ID}"
SMOKE_TITLE="smoke: github tier-b writes ${RUN_TAG}"
DEDUPE_KEY="remogram-smoke:github-writes:${RUN_TAG}"

capture() {
  local file=$1
  shift
  local stderr_file="$RUN_DIR/${file%.json}.stderr"
  local exit_code=0
  remogram "$@" --json >"$RUN_DIR/$file" 2>"$stderr_file" || exit_code=$?
  if [[ ! -s $RUN_DIR/$file ]]; then
    printf '{"ok":false,"type":"capture_error","exit_code":%s,"command_file":"%s"}\n' "$exit_code" "$file" >"$RUN_DIR/$file"
  fi
  python3 -c "import json,sys; d=json.load(open('$RUN_DIR/$file')); assert d.get('ok') is not False, d; print('ok', d.get('type'))"
  return 0
}

echo "GitHub write smoke -> $RUN_DIR"
echo "Title: $SMOKE_TITLE"

capture write_preview_issue_open.json write preview --kind issue_open \
  --title "$SMOKE_TITLE" --body "Disposable smoke issue (${RUN_TAG})." \
  --dedupe-key "$DEDUPE_KEY" --dedupe-check

capture issue_open.json issue open \
  --title "$SMOKE_TITLE" \
  --body "Disposable smoke issue (${RUN_TAG})." \
  --idempotency-key "$DEDUPE_KEY"

ISSUE_NUMBER="$(python3 -c "import json; print(json.load(open('$RUN_DIR/issue_open.json'))['issue_number'])")"
echo "Opened issue #$ISSUE_NUMBER"

capture issue_open_reuse.json issue open \
  --title "$SMOKE_TITLE" \
  --body "Disposable smoke issue (${RUN_TAG})." \
  --idempotency-key "$DEDUPE_KEY"

python3 -c "import json; d=json.load(open('$RUN_DIR/issue_open_reuse.json')); assert d.get('reused_existing') is True, d"

capture issue_comment.json issue comment \
  --number "$ISSUE_NUMBER" \
  --body "Smoke comment from ${RUN_TAG}." \
  --idempotency-key "${DEDUPE_KEY}:comment"

capture issue_view.json issue view --number "$ISSUE_NUMBER"

capture issue_close.json issue close \
  --number "$ISSUE_NUMBER" \
  --idempotency-key "${DEDUPE_KEY}:close"

capture issue_close_reuse.json issue close \
  --number "$ISSUE_NUMBER" \
  --idempotency-key "${DEDUPE_KEY}:close"

python3 -c "import json; d=json.load(open('$RUN_DIR/issue_close_reuse.json')); assert d.get('reused_existing') is True and d.get('already_closed') is True, d"

python3 - <<PY
import json, pathlib
meta = {
  "forge_slug": "github-api-writes",
  "provider": "github-api",
  "run_tag": "$RUN_TAG",
  "issue_number": int("$ISSUE_NUMBER"),
  "dedupe_key": "$DEDUPE_KEY",
  "remogram_config": json.load(open(".remogram.json")),
  "operator_config_path": "$REMOGRAM_OPERATOR_CONFIG",
}
pathlib.Path("$RUN_DIR/meta.json").write_text(json.dumps(meta, indent=2) + "\\n")
PY

echo ""
echo "GitHub Tier B write smoke passed (issue #$ISSUE_NUMBER opened, commented, closed)."
echo "Packets: $RUN_DIR"
