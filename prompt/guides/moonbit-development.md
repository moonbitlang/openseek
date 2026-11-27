Compiler-guided refactoring, project setup, and validation for MoonBit projects.

# MoonBit development

Run `moon --help` to discover commands and `moon <command> --help` for the installed version's arguments and options.

## Compiler-guided work

Run `moon check` via `@builtin/check.mbtx`, fix the reported locations, then recheck. For an API rename that needs compatibility, add the new name, deprecate the old one, and let the compiler identify callers to migrate instead of replacing text blindly.

OpenSeek may append bounded `moon check:` feedback to MoonBit `edit` and `write` results. Use it for immediate feedback; run an explicit check when the summary is incomplete or you need to verify the final state. Review changes to generated `.mbti` files for unintended public API changes.

Look up APIs from the relevant module with `@builtin/ide.mbtx` and `args=["doc", "<query>"]`. Query a symbol or imported package alias, not an English description. If a qualified lookup misses, try a broader symbol query or inspect the imported package before guessing signatures. For structural searches that text cannot express, see `guide:moongrep`.

## Project setup

Keep module metadata and dependency versions in `moon.mod`, and package imports, aliases, and targets in `moon.pkg`. Create `moon.mod` before checking a new project so `moon` does not pick up an unrelated parent module. Use `moon add` for registry dependencies rather than guessing versions. Core packages such as `moonbitlang/core/async/fs` still need a package import but no registry dependency.

## Validation

Check the affected target, run focused package tests, and format the changed sources. Test local package code with `_test.mbt` files, using `_wbtest.mbt` only when private access is needed; a standalone `moon run -e` snippet is not a substitute for testing a local package.

For CLI changes, exercise the affected input modes (file arguments or stdin), successful stdout, and the exit status and diagnostics for invalid input. Use `mooncram` transcripts under `tests/cram/` for lasting coverage of stable CLI contracts. Keep live or networked tests opt-in.
