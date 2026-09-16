# Verified examples

Small MoonBit scripts that teach one feature each, with the explanation in
their comments. They are the source of truth for the language and PTC
material in the system prompt and the PTC tool description: a standalone
markdown link to one of these files is expanded into a fenced block by
`scripts/md_to_mbt_string` when the prompt is generated, so the text is
written once and shown inline.

Every example is verified: `scripts/check-workflows.mbtx` type-checks each
one under `--deny-warn` on wasm in CI, the language examples run under
`tests/cram/examples.md` with their output pinned, and the PTC examples run
through the real host in `agent_tool/mbtx/examples_test.mbt`. When the
toolchain changes what it accepts, the example fails before the prompt can
teach something stale.

- `checked_errors.mbtx`: checked errors as an effect, `suberror`, translation
  at a boundary, `fn main raise`.
- `ptc_guarded_edit.mbtx`: one guarded `edit` from a script and reading
  `result.data`.
- `ptc_search_filter.mbtx`: a `web_search` filtered before it reaches the
  model, keeping URLs and truncation.

Keep each under about 40 lines of code, wasm-safe, and free of workspace side
effects beyond what its arguments name.
