# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

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

- Never encode absence or failure as a sentinel value of the payload's own
  type: no `""` for "no file", no `0`/`-1` for "unknown", no helper that
  aborts when a value is missing. Absence is `T?` (or a dedicated enum
  variant), and every caller handles it as its own branch. This applies on
  the wire too: a JSON field that can be absent is optional or a tagged
  variant, never an empty string the decoder has to recognize. Do not fold
  unrelated errors into the "missing" case either — a stat that fails for any
  reason other than the file being absent must not read as "deleted"; carry
  the failure so the UI can tell the two apart.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Use `moon test` for package- or workspace-scoped MoonBit tests. MoonBit
  supports snapshot testing; when changes affect outputs, run
  `moon test --update` to refresh snapshots.

- From the repository root, the integration gates are `just check`, `just
  test`, and `just build`. They cover the root workspace's native and JS
  targets; `just test` also runs the offline OpenSeek cram tests. For changes
  under `editor/`, also run `just editor-test` for its all-target suite; for
  browser behavior, run `just editor-test-browser` as well.

- The Proton window host, `desktop/app`, is not a member of the root workspace:
  it has a workspace of its own so that nothing else needs a window toolkit to
  build. `just check` still type-checks it; for changes under `desktop/app`,
  also run `just desktop-app-test`, which needs the CEF runtime. See
  `desktop/AGENTS.md`.

- OpenSeek's desktop file editor is the primary downstream, user-facing editor
  host. Use `editor/internal/shell` as the fast build-and-preview loop for
  editor UI work. Existing Viewer UI improvements should flow into OpenSeek
  through its current public APIs with little or no host adaptation. When a new
  editor UI is intended for OpenSeek, implement the corresponding
  `desktop/frontend/fileeditor` adaptation in the same task; do not make the
  slower full desktop build and preview the routine editor inner loop.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. Use snapshot tests to record current
  behavior. For solid, well-defined results (e.g. scientific computations),
  prefer assertion tests. You can use `moon coverage analyze > uncovered.log` to
  see which parts of your code are not covered by tests.
