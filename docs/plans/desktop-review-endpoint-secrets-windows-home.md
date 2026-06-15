# Desktop Review: Endpoint Secrets And Windows Home

## Goal

Address the active desktop PR review comments about endpoint credential leakage
and Windows home-directory resolution.

## Accepted Design

- Keep an explicit desktop `api_key` payload as the highest-priority credential.
- For custom/OpenSeek endpoints (`api_url` present), never fall back to the
  process `DEEPSEEK` environment variable; use the existing placeholder when no
  endpoint-specific key was provided.
- For the official endpoint (`api_url` absent), keep requiring an explicit key
  or `DEEPSEEK`.
- Resolve desktop home paths with `USERPROFILE` first when `OS=Windows_NT`,
  then fall back to `HOME`; non-Windows behavior keeps preferring `HOME`.

## Target Files And Surfaces

- `desktop/internal/host/config.mbt`: credential selection for spawned engine
  runs.
- `desktop/internal/host/config_wbtest.mbt`: white-box tests for credential
  selection.
- `desktop/internal/home/home.mbt`: shared desktop home-directory resolution.
- `desktop/internal/home/home_wbtest.mbt`: white-box tests for Windows and
  non-Windows home resolution.

## API And Interface Diff

- No public MoonBit interface changes are expected.
- Runtime behavior changes only for custom/OpenSeek endpoints without an
  explicit key and for Windows desktop home path resolution.

## Open Questions

- None.

## Next Implementation Step

Add small private helpers for credential and home-directory selection, wire
call sites through them, and cover the review cases with targeted tests.

## Validation Plan

- Run `moon test desktop/internal/host`.
- Run `moon test desktop/internal/home`.
- Run `moon check desktop/internal/host`.
- Run `moon check desktop/internal/home`.
- Run `moon fmt && moon info`.
- Review generated interface diffs and ensure no unrelated dirty files are
  staged.
