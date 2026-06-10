#!/usr/bin/env bash
# Run smoke battery on all configured forges; save packets under runs/<timestamp>/ and render REPORT.md.
#
# Forge list format: slug:config-path:token-env-var
# gitea-api always reads GITEA_TOKEN; gitea.com uses GITEA_COM_TOKEN mapped before capture.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_ID="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="$ROOT/runs/$RUN_ID"
mkdir -p "$RUN_DIR"

echo "Smoke run $RUN_ID -> runs/$RUN_ID"

FORGE_CONFIGS=(
  "gitlab-api:config/remogram.gitlab.json.example:GITLAB_TOKEN"
  "gitea-local:config/remogram.gitea-local.json.example:GITEA_TOKEN"
  "gitea-com:config/remogram.gitea-com.json.example:GITEA_COM_TOKEN"
  "github-api:config/remogram.github.json.example:GITHUB_TOKEN"
)

if ! remogram version --json 2>/dev/null >"$RUN_DIR/.remogram-version.json"; then
  echo null >"$RUN_DIR/.remogram-version.json"
fi

python3 - <<PY
import json, pathlib
run_dir = pathlib.Path("$RUN_DIR")
version_raw = run_dir.joinpath(".remogram-version.json").read_text().strip()
try:
  version = json.loads(version_raw) if version_raw and version_raw != "null" else None
except json.JSONDecodeError:
  version = version_raw or None
manifest = {
  "run_id": "$RUN_ID",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "fixture": {
    "main": "$(git rev-parse main 2>/dev/null || echo null)",
    "feature_smoke_1": "$(git rev-parse feature/smoke-1 2>/dev/null || echo null)",
  },
  "remogram_version": version,
}
run_dir.joinpath("manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
rm -f "$RUN_DIR/.remogram-version.json"

map_gitea_token() {
  local token_var=$1
  GITEA_SMOKE_SAVED_TOKEN="${GITEA_TOKEN:-}"
  if [[ "$token_var" == "GITEA_COM_TOKEN" && -n "${GITEA_COM_TOKEN:-}" ]]; then
    export GITEA_TOKEN="$GITEA_COM_TOKEN"
  fi
}

restore_gitea_token() {
  if [[ -n "${GITEA_SMOKE_SAVED_TOKEN:-}" ]]; then
    export GITEA_TOKEN="$GITEA_SMOKE_SAVED_TOKEN"
  else
    unset GITEA_TOKEN
  fi
  unset GITEA_SMOKE_SAVED_TOKEN
}

for entry in "${FORGE_CONFIGS[@]}"; do
  IFS=: read -r slug config token_var <<<"$entry"
  echo ""
  echo "=== $slug ==="
  if [[ -z "${!token_var:-}" ]] && [[ "$token_var" == "GITHUB_TOKEN" ]] && [[ -n "${GH_TOKEN:-}" ]]; then
    export GITHUB_TOKEN="$GH_TOKEN"
  fi
  if [[ -z "${!token_var:-}" ]]; then
    echo "skip $slug (${token_var} unset)" >&2
    mkdir -p "$RUN_DIR/$slug"
    python3 - <<PY
import json, pathlib
pathlib.Path("$RUN_DIR/$slug/skipped.json").write_text(json.dumps({
  "ok": False,
  "type": "smoke_skipped",
  "reason": "${token_var} not set",
  "forge_slug": "$slug",
}, indent=2) + "\n")
PY
    continue
  fi
  cp "$config" .remogram.json
  map_gitea_token "$token_var"
  export FORGE_SLUG="$slug"
  "$ROOT/scripts/capture-forge-smoke.sh" "$RUN_DIR"
  restore_gitea_token
  unset FORGE_SLUG
done

python3 "$ROOT/scripts/render-smoke-report.py" "$RUN_DIR"
ln -sfn "$RUN_ID" "$ROOT/runs/latest"
cp "$RUN_DIR/REPORT.md" "$ROOT/SMOKE-RESULTS.md"

echo ""
echo "Done. Packets: runs/$RUN_ID/"
echo "Report: SMOKE-RESULTS.md (copy of runs/$RUN_ID/REPORT.md)"
