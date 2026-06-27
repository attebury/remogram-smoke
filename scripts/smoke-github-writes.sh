#!/usr/bin/env bash
# Opt-in live GitHub Tier B write smoke for the remogram-smoke fixture repo.
#
# Mutates forge state (opens then closes a disposable issue). Never run in CI by default.
#
# Prerequisites:
#   - remogram on PATH with github-api Tier B writes (beta.16+), or set REMOGRAM_BIN
#   - export GITHUB_TOKEN=... (repo scope on attebury/remogram-smoke) — same pattern as GITEA_TOKEN
#   - export REMOGRAM_OPERATOR_CONFIG=... (bound write_commands overlay — same pattern as dogfood)
#   - cp config/remogram.github.json.example .remogram.json
#   - cp config/remogram.github-writes.operator.json.example ~/.config/remogram-smoke/github-writes.operator.json
#
# Usage:
#   export GITHUB_TOKEN=...   # or GH_TOKEN (see run-smoke-all.sh)
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

if [[ -z "${GITHUB_TOKEN:-}" && -n "${GH_TOKEN:-}" ]]; then
  export GITHUB_TOKEN="$GH_TOKEN"
fi
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN not set (repo scope PAT on attebury/remogram-smoke)." >&2
  echo "Same pattern as GITEA_TOKEN for read smoke — add to your shell, e.g. ~/.zshrc:" >&2
  echo "  export GITHUB_TOKEN=ghp_..." >&2
  echo "GH_TOKEN is also accepted (mapped to GITHUB_TOKEN)." >&2
  exit 1
fi

if [[ -z "${REMOGRAM_BIN:-}" ]]; then
  for candidate in \
    "$HOME/Documents/lanes/remogram/implement/packages/remogram-cli/bin/remogram.js" \
    "$HOME/Documents/remogram/packages/remogram-cli/bin/remogram.js"; do
    if [[ -f "$candidate" ]]; then
      export REMOGRAM_BIN="$candidate"
      break
    fi
  done
fi

remogram() {
  if [[ -n "${REMOGRAM_BIN:-}" && -f "$REMOGRAM_BIN" ]]; then
    node "$REMOGRAM_BIN" "$@"
  else
    command remogram "$@"
  fi
}

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
  --title "$SMOKE_TITLE" --body "Disposable smoke issue (${RUN_TAG})."

capture issue_open.json issue open \
  --title "$SMOKE_TITLE" \
  --body "Disposable smoke issue (${RUN_TAG})." \
  --idempotency-key "$DEDUPE_KEY"

ISSUE_NUMBER="$(python3 -c "import json; print(json.load(open('$RUN_DIR/issue_open.json'))['issue_number'])")"
echo "Opened issue #$ISSUE_NUMBER"

# GitHub open-issue list can lag after create; retry title idempotency before failing.
reuse_ok=false
for attempt in 1 2 3 4 5; do
  capture issue_open_reuse.json issue open \
    --title "$SMOKE_TITLE" \
    --body "Disposable smoke issue (${RUN_TAG})." \
    --idempotency-key "$DEDUPE_KEY"
  if python3 -c "import json; d=json.load(open('$RUN_DIR/issue_open_reuse.json')); assert d.get('reused_existing') is True, d"; then
    reuse_ok=true
    break
  fi
  if [[ "$attempt" -lt 5 ]]; then
    echo "Title idempotency not visible yet (attempt $attempt/5); waiting..." >&2
    sleep 2
  fi
done
if [[ "$reuse_ok" != true ]]; then
  echo "issue_open title idempotency failed after retries" >&2
  exit 1
fi

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

# Close duplicate opens from GitHub list lag during idempotency retries (if any).
python3 - <<PY
import json, os, subprocess, sys
run_dir = "$RUN_DIR"
title = "$SMOKE_TITLE"
primary = int("$ISSUE_NUMBER")
with open(os.path.join(run_dir, "issue_open_reuse.json")) as f:
    reuse = json.load(f)
extra = reuse.get("issue_number")
if isinstance(extra, int) and extra != primary and reuse.get("created"):
    subprocess.run(
        ["node", os.environ.get("REMOGRAM_BIN", "remogram"), "issue", "close", "--number", str(extra), "--json"],
        check=False,
        env=os.environ,
    )
    print(f"Cleaned up duplicate issue #{extra}", file=sys.stderr)
PY
