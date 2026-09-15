# Writing cram documentation

Cram tests are Markdown usage guides with executable command transcripts.
Use them for a script's arguments, printed output, and exit status. Start with
[Reading files with `read.mbtx`](read-workflow.md) for a complete `.mbtx` example.
For scripts that run Moon commands, see
[Checking, testing, and formatting](validation-workflows.md).

## Run the examples

From the repository root:

```sh
# One document while editing.
moon cram test tests/cram/read-workflow.md --shell bash

# All offline documentation tests; also included in just test and native CI.
just test-cram
```

On Windows, `just test-cram` selects Git Bash from the standard Git installation;
the transcript commands are shell commands, not PowerShell syntax. This selects
the shell only: individual examples may still assume Unix filenames or OS error
messages, as noted in the read guide. The cram CI job currently runs on Linux.

`moon cram test` builds the project's native executables and adds them to
`PATH`. Standalone `.mbtx` examples invoke `moonx` themselves. They can also
run with `moon-cram test tests/cram/read-workflow.md --shell bash` to skip the
project executable build. The script's declared dependencies must be available;
Moon may download them on the first run. The read examples need no model or
credentials.

## Add a script's guide

1. Create `tests/cram/<script>.md`. Explain a useful behavior before showing
   the command that demonstrates it.
2. Put executable transcripts in fenced blocks labeled `mooncram`.
   `$ ` starts a command, `> ` continues it (for example, a heredoc), and the
   following lines are expected standard output. End with `[1]` for an expected
   exit status of 1; omit the marker for success. Use `2>&1` when stderr is part
   of the example's contract.
3. Create small fixtures in the test's temporary working directory. Files
   persist between blocks in a document. Use `$TESTDIR` to locate the script
   relative to the Markdown file.
4. Assign the script path to a variable once, for example
   `READ="$TESTDIR/../../share/workflow/read.mbtx"`. Cram preserves the variable
   between blocks. Each example can then use `moonx "$READ" file.mbt:12`.
   The `$` expands the variable; quotes preserve spaces in the script path.
   Keep setup separate from the expected output.
5. Run the document and review its output. Link it from the relevant usage
   docs. New Markdown files under this directory are picked up by the existing
   test recipe and CI.

Use ordinary `sh` fences for instructions to the reader that should not run
as test cases. Keep output deterministic and small enough to read in full.
These transcripts complement package tests for tool dispatch, sandbox rules,
and other behavior outside the standalone script.

## Update expected output

For an intentional script-output change, generate a candidate transcript:

```sh
moon cram update tests/cram/read-workflow.md --shell bash --assume-yes
git diff --no-index tests/cram/read-workflow.md tests/cram/read-workflow.md.new
```

When expectations change, the update command writes a `.new` file without
`--replace`; unchanged documents produce no new file. Review the diff
(the diff command exits 1 when files differ), then copy the accepted output
back into the guide, remove the `.new` file, and rerun the test. Revise the
surrounding explanation too if the behavior changed. `moon test --update`
updates MoonBit snapshots, not these cram transcripts.
