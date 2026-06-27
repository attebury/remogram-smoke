# remogram-smoke

Minimal cross-forge fixture repo for live **Remogram** smoke tests (read/plan commands by default; optional Tier B write smoke on GitHub).

**Source of truth:** GitLab (`origin`). Other forges are mirrors of the same git content.

**Product repo:** [Remogram](https://github.com/attebury/remogram) — CLI/MCP implementation. This repo is only for live forge fixtures.

## Forges

| Remote | Forge | Provider | Smoke slug | Public URL |
|--------|-------|----------|--------------|------------|
| `origin` | gitlab.com | `gitlab-api` | `gitlab-api` | https://gitlab.com/attebury/remogram-smoke |
| `github` | github.com | `github-api` | `github-api` | https://github.com/attebury/remogram-smoke |
| `gitea-com` | gitea.com | `gitea-api` | `gitea-com` | https://gitea.com/attebury/remogram-smoke |
| `gitea-local` | localhost Gitea | `gitea-api` | `gitea-local` | *(your instance)* |

Create a `gitea.com` mirror manually or run `./scripts/publish-forges.sh` with `GITEA_COM_TOKEN` set (see below). Use the same layout as `gitea-local` with your hosted base URL.

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
export GITEA_TOKEN=...          # local Gitea (localhost:3000)
export GITEA_COM_TOKEN=...      # gitea.com (optional fourth forge)
export GITHUB_TOKEN=...         # or GH_TOKEN
./scripts/run-smoke-all.sh
```

Forges without a token are skipped (recorded in the report). **Both Gitea hosts use the same `gitea-api` provider**, which always reads `GITEA_TOKEN`; the smoke runner maps `GITEA_COM_TOKEN` → `GITEA_TOKEN` only for the `gitea-com` capture pass.

This writes JSON packets under `runs/<timestamp>/` (CLI + `mcp/` subdir per forge), renders `runs/<timestamp>/REPORT.md`, updates `SMOKE-RESULTS.md`, and sets `runs/latest`.

Requires linked remogram checkout at `~/Documents/remogram` (or set `REMOGRAM_ROOT`) for MCP capture.

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

### GitHub Tier B write smoke (opt-in)

Live proof for `issue_open`, `issue_comment`, and `issue_close` against the GitHub mirror. **Mutates forge state** (opens then closes a disposable issue). Never run in CI unless you intend to write to GitHub.

Same two-part setup as Gitea dogfood writes: **forge token in the environment** plus a **bound operator overlay** for `write_commands`.

```bash
cp config/remogram.github.json.example .remogram.json
cp config/remogram.github-writes.operator.json.example ~/.config/remogram-smoke/github-writes.operator.json

export GITHUB_TOKEN=...   # repo scope on attebury/remogram-smoke (add to ~/.zshrc like GITEA_TOKEN)
export REMOGRAM_OPERATOR_CONFIG=$HOME/.config/remogram-smoke/github-writes.operator.json
REMOGRAM_SMOKE_GITHUB_WRITES=1 ./scripts/smoke-github-writes.sh
```

Create a fine-grained or classic PAT with **Issues: read/write** on `attebury/remogram-smoke` only. Do not commit the token; Remogram reads `GITHUB_TOKEN` from the environment only (never from `.remogram.json`).

Packets land under `runs/<timestamp>/github-api-writes/`. Requires remogram with github-api Tier B writes (beta.16+). `cr_open` / `merge execute` live smoke is intentionally out of scope here — those need branch setup and would disturb open PR #1.

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

| Provider | Environment variable | Host |
|----------|---------------------|------|
| `gitlab-api` | `GITLAB_TOKEN` | gitlab.com |
| `gitea-api` (local) | `GITEA_TOKEN` | `baseUrl` in `config/remogram.gitea-local.json.example` |
| `gitea-api` (gitea.com) | `GITEA_COM_TOKEN` | `https://gitea.com` — mapped to `GITEA_TOKEN` at capture time |
| `github-api` | `GITHUB_TOKEN` or `GH_TOKEN` | github.com |

**Write smoke (GitHub):** `GITHUB_TOKEN` + `REMOGRAM_OPERATOR_CONFIG` (see [GitHub Tier B write smoke](#github-tier-b-write-smoke-opt-in)). **Dogfood writes (Gitea):** `GITEA_TOKEN` + `REMOGRAM_OPERATOR_CONFIG` — same split: token proves API auth, operator overlay opts in to write ids.

See `config/*.example` for per-forge `.remogram.json` templates.

### gitea.com bootstrap

1. Create `attebury/remogram-smoke` on gitea.com (or your account path).
2. Add git remote: `git remote add gitea-com https://gitea.com/attebury/remogram-smoke.git`
3. Push branches and open PR #1 (`feature/smoke-1` → `main`):

```bash
export GITEA_COM_TOKEN=...
GITEA_COM_URL=https://gitea.com ./scripts/publish-forges.sh
```

4. Add `GITEA_COM_TOKEN` to your shell (e.g. `~/.zshrc`) alongside `GITEA_TOKEN`.
