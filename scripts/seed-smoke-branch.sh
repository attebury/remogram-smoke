#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

git fetch origin 2>/dev/null || true
git checkout main
git pull --ff-only origin main 2>/dev/null || true

if ! git show-ref --verify --quiet refs/heads/feature/smoke-1; then
  git checkout -b feature/smoke-1
else
  git checkout feature/smoke-1
  git rebase main || git checkout -B feature/smoke-1 main
fi

echo "smoke branch $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> smoke.txt
git add smoke.txt
if git diff --cached --quiet; then
  echo "feature/smoke-1 already seeded"
else
  git commit -m "Seed smoke branch for remogram refs compare."
fi

git checkout main
echo "Seeded feature/smoke-1 at $(git rev-parse feature/smoke-1)"
