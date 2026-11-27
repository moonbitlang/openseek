# Verified examples

These scripts ship as runnable examples. The scripts inlined into the system
prompt live separately in `prompt/examples/` in the source repository.

- `best-of-n.mbtx`: run multiple `openseek run` attempts in separate worktrees;
  see `cmd/openseek/README.md` in the source repository.
- `cli_greet.mbtx`: demonstrate program arguments, exercised by
  `tests/cram/examples.md` and the `mbtx` tool tests.
- `paths_and_env.mbtx`: read paths and environment variables.
- `ptc_search_filter.mbtx`: filter `web_search` results while preserving source
  URLs and truncation, exercised by the `mbtx` host tests.

CI type-checks these scripts with `scripts/check-workflows.mbtx`.
