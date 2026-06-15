# Desktop Review: Active Follow-ups And Stacking

## Goal

Address the active non-outdated review comments on PR #56, leaving the
Windows global skills discovery fix to PR #159 and stacking #56 on that branch.

## Accepted Design

- Teach all desktop packaging jobs to rewrite both SSH and HTTPS GitHub
  submodule URLs through `LEPUS_READ_TOKEN`.
- Refuse registry skill installs when either `<library>/<slug>` or the flat
  `<library>/<slug>.md` user-owned skill already exists without our sidecar.
- Track the in-flight durable session load in frontend model state and ignore
  stale `SessionLoaded` replies that do not match the latest requested session.
- For desktop starts, treat `api_url` as explicit payload state only; do not
  inherit `OPENSEEK_API_URL` when the UI selected DeepSeek.
- Rebase `haoxiang/desktop` onto `origin/haoxiang/windows-global-skills-dir`
  and make PR #56 target that branch after the fixes land.

## Target Files And Surfaces

- `.github/workflows/ci.yml`
- `desktop/internal/skillmarket/library.mbt`
- `desktop/internal/skillmarket/skillmarket_test.mbt`
- `desktop/frontend/model.mbt`
- `desktop/frontend/update.mbt`
- `desktop/frontend/update_wbtest.mbt`
- `desktop/internal/host/config.mbt`
- `desktop/internal/host/config_wbtest.mbt`

## API / Interface Diff

No public MoonBit API is intended to change. The frontend gains a private
`Model.loading_session` field only.

## Open Questions

None for the accepted scope. The cmd/openseek Windows global skills fix remains
owned by #159.

## Next Implementation Step

Implement the local code and workflow fixes, run targeted validation, commit,
then rebase and push the desktop branch as a stack on #159.

## Validation Plan

- `moon fmt`
- `moon info`
- `moon check`
- `moon test desktop/internal/host`
- `moon test desktop/internal/skillmarket`
- `moon test desktop/frontend`
