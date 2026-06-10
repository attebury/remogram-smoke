#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GITEA_URL="${GITEA_URL:-http://localhost:3000}"
GITEA_COM_URL="${GITEA_COM_URL:-https://gitea.com}"
GITEA_USER="${GITEA_USER:-attebury}"
GITHUB_OWNER="${GITHUB_OWNER:-attebury}"
REPO_NAME="${REPO_NAME:-remogram-smoke}"

ensure_gitea_repo() {
  local api_url="$1"
  local token="$2"
  local label="$3"
  if [[ -z "$token" ]]; then
    echo "${label}: token not set; skipping" >&2
    return 1
  fi
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: token ${token}" \
    "${api_url}/api/v1/repos/${GITEA_USER}/${REPO_NAME}")"
  if [[ "$code" == "200" ]]; then
    echo "${label} repo ${GITEA_USER}/${REPO_NAME} exists"
    return 0
  fi
  curl -s -X POST \
    -H "Authorization: token ${token}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${REPO_NAME}\",\"private\":false,\"auto_init\":false}" \
    "${api_url}/api/v1/user/repos" | python3 -c "import json,sys; d=json.load(sys.stdin); print('created', d.get('full_name', d.get('message')))"
}

ensure_gitea_repo_local() {
  ensure_gitea_repo "$GITEA_URL" "${GITEA_TOKEN:-}" "Gitea local"
}

ensure_gitea_repo_com() {
  ensure_gitea_repo "$GITEA_COM_URL" "${GITEA_COM_TOKEN:-}" "Gitea.com"
}

ensure_github_repo() {
  if gh repo view "${GITHUB_OWNER}/${REPO_NAME}" >/dev/null 2>&1; then
    echo "GitHub repo ${GITHUB_OWNER}/${REPO_NAME} exists"
  else
    gh repo create "${GITHUB_OWNER}/${REPO_NAME}" --public --description "remogram cross-forge smoke fixture"
  fi
}

add_remote_once() {
  local name="$1" url="$2"
  if git remote get-url "$name" >/dev/null 2>&1; then
    git remote set-url "$name" "$url"
  else
    git remote add "$name" "$url"
  fi
}

ensure_gitea_repo_local || true
ensure_gitea_repo_com || true
ensure_github_repo

add_remote_once gitea-local "${GITEA_URL}/${GITEA_USER}/${REPO_NAME}.git"
add_remote_once gitea-com "${GITEA_COM_URL}/${GITEA_USER}/${REPO_NAME}.git"
add_remote_once github "https://github.com/${GITHUB_OWNER}/${REPO_NAME}.git"

push_remote() {
  local remote=$1
  local token=$2
  local base_url=$3
  if ! git remote get-url "$remote" >/dev/null 2>&1; then
    return 0
  fi
  echo "Pushing main and feature/smoke-1 -> ${remote}"
  if [[ -n "$token" && "$base_url" == http* ]]; then
    local auth_url="${base_url#https://}"
    auth_url="${auth_url#http://}"
    git push "https://oauth2:${token}@${auth_url}/${GITEA_USER}/${REPO_NAME}.git" main \
      || echo "warn: push main to ${remote} failed" >&2
    git push "https://oauth2:${token}@${auth_url}/${GITEA_USER}/${REPO_NAME}.git" feature/smoke-1 \
      2>/dev/null || git push "https://oauth2:${token}@${auth_url}/${GITEA_USER}/${REPO_NAME}.git" feature/smoke-1 \
      || echo "warn: push feature/smoke-1 to ${remote} failed" >&2
    git branch -u "$remote/main" main 2>/dev/null || true
    return 0
  fi
  git push -u "$remote" main || echo "warn: push main to ${remote} failed" >&2
  git push -u "$remote" feature/smoke-1 2>/dev/null || git push "$remote" feature/smoke-1 || echo "warn: push feature/smoke-1 to ${remote} failed" >&2
}

push_remote gitea-local "${GITEA_TOKEN:-}" "$GITEA_URL"
push_remote gitea-com "${GITEA_COM_TOKEN:-}" "$GITEA_COM_URL"

for remote in github origin; do
  if git remote get-url "$remote" >/dev/null 2>&1; then
    echo "Pushing main and feature/smoke-1 -> ${remote}"
    git push -u "$remote" main || echo "warn: push main to ${remote} failed" >&2
    git push -u "$remote" feature/smoke-1 2>/dev/null || git push "$remote" feature/smoke-1 || echo "warn: push feature/smoke-1 to ${remote} failed" >&2
  fi
done

echo "Publish complete. Open MR/PR #1 on each forge if not already present."
echo "GitLab push requires GITLAB_TOKEN or SSH; use:"
echo "  git push https://oauth2:\${GITLAB_TOKEN}@gitlab.com/${GITHUB_OWNER}/${REPO_NAME}.git main"
