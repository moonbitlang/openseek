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

- For MoonBit code changes, finish with `moon info && moon fmt` to update the
  interfaces and format the code. Check that the `.mbti` diffs are expected.

- Use `moon test` for package- or workspace-scoped MoonBit tests. MoonBit
  supports snapshot testing; when expected outputs change, run
  `moon test --update` and review the updated snapshots.

- For implementation changes, run the root integration gates: `just check`,
  `just test`, and `just build`. They cover the root workspace's native and JS
  targets; `just test` also runs the offline OpenSeek cram tests. For editor
  implementation changes, also run `just editor-test` for its all-target suite;
  for browser behavior, run `just editor-test-browser` as well. For changes
  limited to documentation, check the diff and referenced paths or commands.

- `desktop/app` is outside the root workspace and builds in its own
  `desktop/app/moon.work`, so the root gates do not cover it. For changes
  that reach the window host, also run `just desktop-app-check` and
  `just desktop-app-test`.

- For editor UI work, follow `editor/AGENTS.md` for the preview loop and
  OpenSeek integration requirements.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. Use snapshot tests to record current
  behavior. For solid, well-defined results (e.g. scientific computations),
  prefer assertion tests. You can use `moon coverage analyze > uncovered.log` to
  see which parts of your code are not covered by tests.
