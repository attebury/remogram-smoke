# remogram-smoke

Minimal cross-forge fixture repo for live **remogram** v1 smoke tests (read/plan commands only).

**Source of truth:** GitLab (`origin`). Other forges are mirrors created from this repo.

## Forges

| Remote | Forge | Provider |
|--------|-------|----------|
| `origin` | gitlab.com | `gitlab-api` |
| `gitea-local` | localhost Gitea | `gitea-api` |
| `github` | github.com | `github-api` |

Create gitea.com mirror manually if needed; use the same layout as `gitea-local` with your hosted base URL.

## Bootstrap

```bash
git clone https://gitlab.com/attebury/remogram-smoke.git
cd remogram-smoke
cp config/remogram.gitlab.json.example .remogram.json   # adjust owner if needed
export GITLAB_TOKEN=...                                 # gitlab-api
remogram doctor --json
```

Switch forge by copying the matching example to `.remogram.json` (or set `REMOGRAM_CWD` when using MCP from this directory).

## Fixture shape

- **`main`** — default branch with this README and `smoke.txt`
- **`feature/smoke-1`** — one commit ahead of `main` for `refs compare`
- **Open MR/PR #1** — `feature/smoke-1` → `main` for `pr view`, `pr checks`, `merge plan`

Re-seed after resetting a forge:

```bash
./scripts/seed-smoke-branch.sh
./scripts/publish-forges.sh          # push branches to all configured remotes
```

## Smoke battery

Capture packets for all forges (requires tokens in the environment):

```bash
export GITLAB_TOKEN=...
export GITEA_TOKEN=...
export GITHUB_TOKEN=...   # or GH_TOKEN
./scripts/run-smoke-all.sh
```

This writes JSON packets under `runs/<timestamp>/`, renders `runs/<timestamp>/REPORT.md`, updates `SMOKE-RESULTS.md`, and sets `runs/latest`.

Quick single-forge check (uses current `.remogram.json` only):

```bash
./scripts/smoke-commands.sh
```

Or run manually:

```bash
remogram doctor --json
remogram provider capabilities --json
remogram repo status --json
remogram refs compare --base main --head feature/smoke-1 --json
remogram pr view --number 1 --json
remogram pr checks --number 1 --json
remogram merge plan --number 1 --json
```

On local Gitea without status posting, `check_conclusion: "missing"` is an expected forge fact.

Compare runs visually via `SMOKE-RESULTS.md` or any `runs/*/REPORT.md` (summary tables + expandable full JSON per forge).

**Historical note:** GitHub `pr view` returned `oversized_raw_output` before remogram GraphQL normalization (remogram PR #23); re-run `./scripts/run-smoke-all.sh` after upgrading remogram to confirm.

## GitLab push (source of truth)

HTTPS push needs a personal access token:

```bash
export GITLAB_TOKEN=...
git push "https://oauth2:${GITLAB_TOKEN}@gitlab.com/attebury/remogram-smoke.git" main
git push "https://oauth2:${GITLAB_TOKEN}@gitlab.com/attebury/remogram-smoke.git" feature/smoke-1
```

Then open MR !1: `feature/smoke-1` → `main` in GitLab UI, or use the API with `GITLAB_TOKEN`.

## Auth

| Provider | Environment variable |
|----------|---------------------|
| `gitlab-api` | `GITLAB_TOKEN` |
| `gitea-api` | `GITEA_TOKEN` |
| `github-api` | `GITHUB_TOKEN` or `GH_TOKEN` |

See `config/*.example` for per-forge `.remogram.json` templates.
