# Smoke run artifacts

Each `./scripts/run-smoke-all.sh` execution creates `runs/<UTC-timestamp>/`:

```
runs/2026-06-10T12-00-00Z/
  manifest.json          # run metadata and fixture SHAs
  REPORT.md              # visual comparison for this run
  gitlab-api/
    doctor.json
    provider_capabilities.json
    repo_status.json
    refs_compare.json
    pr_view.json
    pr_checks.json
    merge_plan.json
    meta.json
  gitea-local/
  gitea-com/
  github-api/
```

`runs/latest` is a symlink to the most recent run. Root `SMOKE-RESULTS.md` is copied from the latest `REPORT.md` for easy browsing in the forge UI.

Commit run directories to keep a history of cross-forge packet comparisons over time.
