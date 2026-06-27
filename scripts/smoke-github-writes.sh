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
# Optional:
#   SMOKE_RUN_DIR=runs/manual-github-writes
#   SMOKE_CHECK_TITLE_IDEMPOTENCY=1  — warn-only title reuse check after 5s (GitHub list lag)
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

preflight_github_issues_token() {
  local owner repo status body
  owner="$(python3 -c "import json; print(json.load(open('.remogram.json'))['owner'])")"
  repo="$(python3 -c "import json; print(json.load(open('.remogram.json'))['repo'])")"
  status="$(curl -sS -o /tmp/remogram-smoke-issues-preflight.json -w '%{http_code}' \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${owner}/${repo}/issues?state=open&per_page=1")"
  if [[ "$status" == "200" ]]; then
    return 0
  fi
  body="$(python3 -c "import json; print(json.load(open('/tmp/remogram-smoke-issues-preflight.json')).get('message',''))" 2>/dev/null || true)"
  echo "GitHub Issues API preflight failed (HTTP ${status}${body:+: ${body}})." >&2
  echo "Fine-grained PAT on ${owner}/${repo} needs Issues: Read and write (not write-only)." >&2
  echo "Regenerate at: https://github.com/settings/personal-access-tokens" >&2
  exit 1
}

cleanup_smoke_issues() {
  python3 - <<'PY'
import json, os, subprocess, urllib.request

cfg = json.load(open(".remogram.json"))
owner, repo = cfg["owner"], cfg["repo"]
token = os.environ["GITHUB_TOKEN"]
prefix = "smoke: github tier-b writes"
url = f"https://api.github.com/repos/{owner}/{repo}/issues?state=open&per_page=100"
req = urllib.request.Request(url, headers={
    "Authorization": f"Bearer {token}",
    "Accept": "application/vnd.github+json",
})
try:
    with urllib.request.urlopen(req) as resp:
        items = json.load(resp)
except Exception as exc:
    print(f"cleanup skip: {exc}", flush=True)
    raise SystemExit(0)
bin_path = os.environ.get("REMOGRAM_BIN")
for issue in items:
    if issue.get("pull_request"):
        continue
    title = issue.get("title") or ""
    if not title.startswith(prefix):
        continue
    number = issue.get("number")
    if not number:
        continue
    cmd = ["remogram", "issue", "close", "--number", str(number), "--json"]
    if bin_path and os.path.isfile(bin_path):
        cmd = ["node", bin_path, "issue", "close", "--number", str(number), "--json"]
    subprocess.run(cmd, check=False, env=os.environ)
    print(f"cleanup closed #{number}", flush=True)
PY
}

capture() {
  local file=$1
  shift
  local stderr_file="$RUN_DIR/${file%.json}.stderr"
  local exit_code=0
  remogram "$@" --json >"$RUN_DIR/$file" 2>"$stderr_file" || exit_code=$?
  if [[ ! -s $RUN_DIR/$file ]]; then
    printf '{"ok":false,"type":"capture_error","exit_code":%s,"command_file":"%s"}\n' "$exit_code" "$file" >"$RUN_DIR/$file"
  fi
  if ! python3 -c "
import json, sys
d = json.load(open('$RUN_DIR/$file'))
if d.get('ok') is False:
    code = d.get('error_code', 'unknown')
    msg = d.get('error_message', d)
    print(f'FAIL $file: {code} — {msg}', file=sys.stderr)
    sys.exit(1)
print('ok', d.get('type'))
"; then
    if [[ -f "$stderr_file" && -s "$stderr_file" ]]; then
      echo "--- stderr ($file) ---" >&2
      cat "$stderr_file" >&2
    fi
    exit 1
  fi
}

preflight_github_issues_token

RUN_ID="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="${SMOKE_RUN_DIR:-$ROOT/runs/$RUN_ID/github-api-writes}"
mkdir -p "$RUN_DIR"

RUN_TAG="${RUN_ID}"
SMOKE_TITLE="smoke: github tier-b writes ${RUN_TAG}"
DEDUPE_KEY="remogram-smoke:github-writes:${RUN_TAG}"

echo "GitHub write smoke -> $RUN_DIR"
echo "Title: $SMOKE_TITLE"

echo "Cleaning up prior smoke issues (if any)..." >&2
cleanup_smoke_issues || true

capture write_preview_issue_open.json write preview --kind issue_open \
  --title "$SMOKE_TITLE" --body "Disposable smoke issue (${RUN_TAG})."

capture issue_open.json issue open \
  --title "$SMOKE_TITLE" \
  --body "Disposable smoke issue (${RUN_TAG})." \
  --idempotency-key "$DEDUPE_KEY"

ISSUE_NUMBER="$(python3 -c "import json; print(json.load(open('$RUN_DIR/issue_open.json'))['issue_number'])")"
echo "Opened issue #$ISSUE_NUMBER"

if [[ "${SMOKE_CHECK_TITLE_IDEMPOTENCY:-}" == "1" ]]; then
  echo "Optional title idempotency check (warn-only; GitHub open-issue list can lag)..." >&2
  sleep 5
  remogram issue open \
    --title "$SMOKE_TITLE" \
    --body "Disposable smoke issue (${RUN_TAG})." \
    --idempotency-key "$DEDUPE_KEY" \
    --json >"$RUN_DIR/issue_open_idempotency_optional.json" 2>"$RUN_DIR/issue_open_idempotency_optional.stderr" || true
  python3 -c "
import json
d = json.load(open('$RUN_DIR/issue_open_idempotency_optional.json'))
if d.get('reused_existing'):
    print('title idempotency: reused #' + str(d.get('issue_number')), flush=True)
elif d.get('created'):
    print('title idempotency: WARN list lag created #' + str(d.get('issue_number')) + ' (not a smoke failure)', flush=True)
else:
    print('title idempotency: WARN ' + str(d.get('error_code') or d), flush=True)
"
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

cleanup_smoke_issues || true

echo ""
echo "GitHub Tier B write smoke passed (issue #$ISSUE_NUMBER opened, commented, closed)."
echo "Packets: $RUN_DIR"
