# Verified examples

Small MoonBit scripts that teach one feature each, with the explanation in
their comments. They are the source of truth for the language and PTC
material in the system prompt and the PTC tool description: a standalone
markdown link to one of these files is expanded into a fenced block by
`scripts/md_to_mbt_string` when the prompt is generated, so the text is
written once and shown inline.

Every example is verified: `scripts/check-workflows.mbtx` type-checks each
one under `--deny-warn` on wasm in CI, the examples with deterministic output
run under `tests/cram/examples.md` with their output pinned, and the PTC
examples run through the real host in `agent_tool/mbtx/examples_test.mbt`.
The rest — the ones that spawn `moon` or `rg`, glob the working directory, or
read the environment — are type-checked only, since what they print depends
on the checkout they run in. When the toolchain changes what it accepts, the
example fails before the prompt can teach something stale.

Part 1 of the prompt teaches the tooling:

- `command_output.mbtx`: `@shell.Cmd(...).output()` and its three accessors,
  including a non-zero exit that is not a failure.
- `check_diagnostics.mbtx`: streaming line-delimited `moon check` JSON with
  `each_line` and matching it as `@json.parse` output.
- `cli_count_input.mbtx`: an `argparse` CLI reading a file or stdin through
  async IO.
- `workflow_scouts.mbtx`: the `moonbitlang/workflow` handoff a `subrun=true`
  snippet gets — fan out scouts, keep the answers that arrived, report the
  spend.

The reusable-script form is taught from `share/workflow/check.mbtx`, the
bundled workflow itself, so the prompt shows the same file `@builtin/` runs.
`paths_and_env.mbtx` and `cli_greet.mbtx` are verified here but not linked
from the prompt; `cli_greet.mbtx` is the fixture
`agent_tool/mbtx/mbtx_test.mbt` drives through the real tool to pin the `args`
contract.

Part 2 teaches the language:

- `checked_errors.mbtx`: checked errors as an effect, `suberror`, translation
  at a boundary, `fn main raise`.
- `syntax_basics.mbtx`: bindings, negation, `Map([])`, match arms, lambdas.
- `strings_and_views.mbtx`: interpolation, multi-line literals, code units,
  clamping views, shortlex ordering, in-place sort, map lookup, JSON
  patterns.

The PTC tool description teaches host calls:

- `ptc_guarded_edit.mbtx`: one guarded `edit` from a script and reading
  `result.data`.
- `ptc_search_filter.mbtx`: a `web_search` filtered before it reaches the
  model, keeping URLs and truncation.

Keep each under about 40 lines of code, wasm-safe, and free of workspace side
effects beyond what its arguments name.
