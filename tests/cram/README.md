# Writing CLI documentation tests

These Markdown usage guides run with `moon testcli`, the MoonBit toolchain's
CLI test runner. Fences still use the language name `mooncram`. Start with
[Reading files](read-workflow.md), [Validation workflows](validation-workflows.md),
or [File artifacts](file-artifacts.md) for existing scenarios.

## Run the examples

Use a MoonBit toolchain with `moon testcli` (`moon testcli --help` checks it).
From the repository root:

```sh
# Validate syntax and target resolution without executing commands.
moon testcli check tests/cram
moon -C openseek_tui testcli check tests/cram

# One document while editing.
moon testcli test tests/cram/read-workflow.md

# All offline CLI documentation tests; also included in just test and native CI.
just test-cli
```

Local executable cases and `.mbtx` scripts use testcli's default Wasm backend.
The TUI suite starts in its own module because fence module declarations
must match the `moon.mod` in testcli's startup directory. First builds may download
package dependencies. Tests make no external model API calls.

`testcli` starts each case in the Markdown file's directory unless its fence has
`#cwd(relative/path)`; all declared directories must already exist. It provides
no temporary directory and does not expand shell variables, run heredocs, or
accept arbitrary binaries. Every command/pipeline segment starts with `moonx`
and names a local script, a full local executable package in a module-declared
fence, or an exact remote package version. Commands occupy one source line.

## Add a case

1. Create `tests/cram/<behavior>.md`, explaining the behavior before the example.
2. Prefer direct `moonx ../../share/examples/example.mbtx` calls for scripts. For
   the engine, declare `mooncram moonbitlang/openseek` and invoke
   `moonx moonbitlang/openseek <args>`; testcli builds the selected package.
3. Write expected stdout below the command. End with `[1]` for exit status 1;
   omit it for success. To assert stderr, include both `@STDOUT` and `@STDERR`
   markers, using `(empty)` or `(ignore)` where appropriate. Direct cases do
   not accept `2>&1`. Use exact output for stable values and narrow `(glob)` or
   `(regex)` patterns for variable fields.
4. For cases needing temporary files or process control, add one standalone
   `.mbtx` under `fixtures/`, named after the behavior being tested. Invoke it
   directly, for example `moonx fixtures/cancel-on-stdin-eof.mbtx`.
   Put setup and commands together in that script, and clean up temporary
   directories with `defer`. Use `@shell.Cmd("moon", ["run", "--quiet", ...])`
   to build and run the real program; no artifact-path helper is needed. Print
   the observed exit codes, relevant output, and file properties so expectations
   stay in the Markdown snapshot. Use `@process` pipes when stdin timing is
   the behavior under test.
   Keep simple commands and pipelines directly in the document.
5. Run `check`, then `test`, review the output, and link the guide from usage docs.
   New Markdown files under this directory are discovered by the recipe and CI.

The scripts use MoonBit's standard library and need no Bash or sh interpreter.
Each script can be built on its own, including in the standalone TUI release.
Unix filenames and OS error text still make some cases platform-specific; CI
runs this suite on Linux.

Use ordinary `sh` fences for commands the reader should run. Read the toolchain's
embedded reference with `moon testcli docs commands`, `moon testcli docs expectations`,
and `moon testcli docs execution` when adding a new kind of case.

## Update expected output

For an intentional output change, preview the update, then apply and review it:

```sh
moon testcli update --timeout-ms 300000 tests/cram/read-workflow.md --dry-run
moon testcli update --timeout-ms 300000 tests/cram/read-workflow.md
git diff -- tests/cram/read-workflow.md
moon testcli test tests/cram/read-workflow.md
```

`update` writes the original Markdown files directly and may normalize passing
cases too. `--dry-run` previews edits but still executes programs. Use `check`
for validation without execution and `test` for the pass/fail gate; an update
preview can exit successfully despite output mismatches. Revise the prose too
when the behavior changes. `moon test --update` updates MoonBit snapshots rather
than these CLI transcripts.
