You are running a MoonBit coding-agent benchmark.

Workspace: {{WORKSPACE}}

Build a native-only MoonBit async CLI in that workspace that computes file
statistics by reading many files concurrently. This measures discovery and
correct use of the `moonbitlang/async` file/process APIs plus deterministic
output under concurrency.

Requirements:

- Create a current MoonBit project using `moon.mod`, not `moon.mod.json`.
- Depend on `moonbitlang/async`. The program is native-only.
- Implement a native CLI at `cmd/dirstats` with two modes:
  - `cmd/dirstats -- <dir>` — recursively walk `<dir>` and gather every regular
    file.
  - `cmd/dirstats -- --stdin` — read a newline-separated list of file paths
    from stdin.
- In both modes, read the files **concurrently** (with a bounded number of
  in-flight reads, not one giant unbounded fan-out) and print a single compact
  JSON object on stdout with exactly these keys in this order and no spaces:
  `{"files":<N>,"lines":<L>,"bytes":<B>}` where
  - `N` is the number of files read,
  - `L` is the total number of newline (`\n`) bytes across all files,
  - `B` is the total number of bytes across all files.
- The output must be identical regardless of the order in which concurrent
  reads complete.
- If a listed or walked path cannot be read, print a clean, single-line error
  to stderr containing the word `error`, then exit non-zero. A MoonBit panic,
  abort, or debug stack must never reach the output.
- Add black-box tests that build a small fixture tree and assert the counts,
  including an empty file and a nested directory.

Validation expectations before finishing:

- Run `moon check --target native`.
- Run `moon test --target native`.
- Run `moon fmt`.
- Run at least these CLI probes:
  - `--stdin` listing one file with known content, checking the exact JSON.
  - `--stdin` listing an empty file → `{"files":1,"lines":0,"bytes":0}`.
  - `--stdin` listing a nonexistent path (must error, not panic).
- Finish only after reporting the validation commands you ran and any remaining
  caveats.
