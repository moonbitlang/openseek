# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Task Scope

- Use the requested outcome and explicit exclusions to define the change scope.
  Apply these conventions to the code and contracts touched by that work.
  Include broader cleanup or behavior changes when they are part of the
  requested outcome.
- Tie new defensive behavior to an existing contract or an agreed product
  requirement. State the triggering input or user action and the expected
  result so the check has a concrete purpose and completion criterion.

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata. `moon.mod.json` is the legacy manifest format.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

- When adding or changing an API, represent expected absence with `T?` or a
  dedicated enum variant, including in JSON payloads. Carry operational
  failures through an error channel or a tagged error case, and handle each
  result according to the owning API's contract. Changing what absence means
  is a behavior change and follows the task scope.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. Use `moon ide --help` for the available commands.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. Review `.mbti` diffs for public signature changes;
  use behavior tests to check runtime effects.

- For MoonBit code changes, finish with `moon info` then `moon fmt`, selecting
  the affected packages with path arguments. Check that the `.mbti` diffs are
  expected.

- Use `moon test` for package- or workspace-scoped MoonBit tests. MoonBit
  supports snapshot testing; when expected outputs change, run
  `moon test --update` and review the updated snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. Use snapshot tests to record current
  behavior. For solid, well-defined results (e.g. scientific computations),
  prefer assertion tests. You can use `moon coverage analyze > uncovered.log` to
  see which parts of your code are not covered by tests.

## Validation By Change Scope

Start with the smallest checks that exercise the changed behavior. Expand to
consumers, integration paths, or more targets when shared behavior/styles,
public contracts, dependencies, or build configuration affect them; explain why.
Report checks, results, failures, and remaining gaps. A green backend suite does
not establish UI correctness.

Commands below run from the repository root.

| Change | Targeted checks |
| --- | --- |
| Documentation only | Diff and referenced paths/commands; affected cram document if executable examples change. |
| Pure CSS or static presentation assets | Rebuild/serve the frontend and inspect affected UI or run focused browser scenarios, including relevant themes, viewports, and interactions. No automatic MoonBit, backend/CLI, or root gates. |
| MoonBit source | `moon check` and relevant `moon test` cases for affected packages/targets; update interfaces and formatting as above. |
| CLI arguments, output, exit status, or requests | Owning package tests and matching document under `tests/cram/` or `openseek_tui/tests/cram/`. |
| Background jobs, turn completion, or serve controls | Owning package tests and `just test-turn-finish`. |
| Subagents, review, or workers | Owning package tests and the matching integration script from `test-subagents` in [justfile](justfile). |
| Bundled workflows | Relevant cram document, `just check-workflows` for compilation, or `just test-workflows` for hosted behavior. |
| Service startup or engine resolution | Owning native package tests and `just test-app-server`. |
| Editor, Desktop, or session-viewer UI/host integration | [Editor guidance](editor/AGENTS.md), [Desktop guidance](desktop/AGENTS.md), or [session-viewer browser tests](cmd/viz_app/e2e/README.md). |

Command details: `moon test --help`,
[cram](tests/cram/README.md), and [integration tests](tests/integration/README.md).
Select packages/files/test names for MoonBit tests and individual scripts for
CLI integration; script assertions in `main` require `moon run`, not `moon test`.

Full gates remain available when justified or explicitly required: `just check`,
`just test`, and `just build`; their individual test groups are in [justfile](justfile).
Root gates exclude `desktop/app` and browser suites; use the host-specific
entries in the linked guides. CI requirements are unchanged.
