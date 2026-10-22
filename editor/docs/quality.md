# Quality Gates

Current docs and package READMEs are product contracts. Keep cross-package
architecture in `docs/architecture.md` and package details in package READMEs.

## Select Relevant Checks

Apply the [root scope and expansion rules](../../AGENTS.md#validation-by-change-scope).
Commands here run from `editor/`.

| Change | Targeted checks |
| --- | --- |
| CSS or presentation assets | Rebuild the frontend and preview affected UI in `internal/shell`, or run a focused browser scenario. |
| DOM-free model, parser, provider, or state logic | Check/test affected packages and targets with ordinary/headless tests; use `--warn-list +73 --deny-warn` for checks. |
| DOM, layout, input/focus, or browser lifecycle | JS checks for changed MoonBit packages and focused Playwright component tests; use smoke tests for workbench/server/host integration. |
| Public API, dependencies, or target support | Review manifests/interfaces and check/test affected consumers; select `--target all` when all supported targets are affected. |
| OpenSeek adapters | Targeted JS checks and affected OpenSeek UI path; [Desktop guidance](../../desktop/AGENTS.md) for window-host behavior. |

Build fresh frontend/scenario assets before browser tests. Command details and
layer ownership: [harness](harness.md) and [browser tests](../tests/browser/README.md).

## Full Editor Gates

Available when justified or explicitly required; these commands run from `editor/`:

```sh
moon check --target all --warn-list +73 --deny-warn
moon fmt --check
just test
just build
just test-browser-smoke
```

## Guardrails

- Product code never imports `vscode/`, `codemirror/`, or the reference shell.
- Shared packages remain FFI-free; js/native-only packages declare their target.
- Viewer packages use only Rabbita's DOM/JS bindings, not its TEA framework.
- The shell/backend remains optional to embedders.
- The check gate is read-only: `moon check --target all --warn-list +73 --deny-warn` covers
  every target and `moon fmt --check` verifies formatting.
- Review `moon.pkg` changes against `docs/architecture.md`, and review public API
  changes through `pkg.generated.mbti`.
- Every public declaration should have a non-test production consumer. Tests do
  not justify public visibility. A deliberate external or staged contract with
  no repository consumer belongs in the owning package's `exports.mbt`, where
  `moon ide analyze` records the exception explicitly.
- Implementation structs and enums default to abstract package types: use a
  plain `struct X` or `enum X` plus the required public operations. Expose a
  concrete layout only when production consumers must construct, mutate, or
  pattern-match it. Retain `derive(Debug)` on debugging-facing types even when
  no production call site invokes the generated implementation.
- Do not add architecture lint for a one-time design decision. Automate a
  boundary only after the same concrete failure recurs, and keep the check
  generic rather than naming current methods or implementation types.

## Reference Tests

Use `*_reference_test.mbt` / `*_reference_wbtest.mbt` when a test is traceable
to a pinned Monaco, VS Code, or CodeMirror source test or behavior cluster.

- Name the source path and pinned revision in the file or test comment.
- Preserve source labels, inputs, outputs, ordering, and boundary values when
  they are part of the behavior under test.
- Within the selected source-test or behavior scope, keep unsupported cases
  visible as `SKIPPED` with a product-boundary reason instead of silently
  deleting them.
- Test observable behavior and algorithmic invariants. TypeScript interfaces,
  class hierarchies, and private field layout are not conformance contracts.
