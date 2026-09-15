# Reading files with `read.mbtx`

This page is both a usage guide and an executable test of
[`read.mbtx`](../../share/workflow/read.mbtx). Each `mooncram` block shows a
shell command after `$`, followed by its expected output. `[1]` means the
command must exit with status 1; without it, success is expected.

Run this page from the repository root:

```sh
moon cram test tests/cram/read-workflow.md --shell bash
```

These transcripts assume Unix filesystem behavior. On Windows, `just test-cram`
selects Git Bash, but that alone does not make this page portable: the `log:12`
fixture is not an ordinary Windows filename, and OS error text can differ.
The page has been verified locally on macOS; the cram CI job runs on Linux,
with no Windows cram job currently configured.

In OpenSeek, the equivalent of the first example below is:

```json
{"filename":"@builtin/read.mbtx","args":["sample.mbt"]}
```

These tests run the script directly with `moonx`; they verify its text
output and exit status. The [mbtx package tests](../../agent_tool/mbtx/read_workflow_test.mbt)
cover execution through the tool, including sandbox and output-limit behavior.
See [Writing cram documentation](README.md) to add examples for another script.

## Set up the examples

Cram gives this page a temporary working directory. Files persist between
blocks; `$TESTDIR` points to the directory containing this Markdown file.
Define `READ` once so each example can focus on the script's arguments:

```mooncram
$ READ="$TESTDIR/../../share/workflow/read.mbtx"
```

Cram preserves this shell variable between blocks. `moonx "$READ"` runs the
script; quoting the expanded path keeps spaces in it intact. Arguments after
the script path are passed to the script.

Create a three-line file with a trailing newline:

```mooncram
$ cat > sample.mbt <<'EOF'
> first
> selected
> last
> EOF
```

The trailing newline counts as a fourth, empty line. The remaining fixtures
include a file without a trailing newline, an empty file, and a directory:

```mooncram
$ printf 'whole file' > note.txt
```

```mooncram
$ touch empty.txt
```

```mooncram
$ mkdir dir
```

## Read a whole file

Every file gets a JSON-quoted heading, a numbered body, and a `<system>`
footer. The footer fields describe the selected output:

| Field | Meaning |
| --- | --- |
| `start_line` | Requested first line (1-based). |
| `shown_lines` | Number of lines emitted, including a partially emitted line. |
| `total_lines` | Number of lines in the whole file, including a final blank line. |
| `truncated` | Whether the output budget prevented the full selected range from being shown. |

```mooncram
$ moonx "$READ" sample.mbt
=== "sample.mbt" ===
1 |first
2 |selected
3 |last
4 |
<system>start_line=1 shown_lines=4 total_lines=4 truncated=false</system>
```

## Read an inclusive range or a tail

Selectors are `path`, `path:start`, or `path:start:end`; lines are 1-based
and both ends are included.

```mooncram
$ moonx "$READ" sample.mbt:2:3
=== "sample.mbt" ===
2 |selected
3 |last
<system>start_line=2 shown_lines=2 total_lines=4 truncated=false</system>
```

```mooncram
$ moonx "$READ" sample.mbt:3
=== "sample.mbt" ===
3 |last
4 |
<system>start_line=3 shown_lines=2 total_lines=4 truncated=false</system>
```

## Read past EOF or read an empty file

A range beyond the end is not an error: the footer reports what the file
holds. An empty file says so explicitly. Several selectors in one call come
back in order, each under its own heading.

```mooncram
$ moonx "$READ" sample.mbt:10:20 empty.txt
=== "sample.mbt" ===
<system>start_line=10 shown_lines=0 total_lines=4 truncated=false</system>
=== "empty.txt" ===
<system>start_line=1 shown_lines=0 total_lines=0 truncated=false note=empty file</system>
```

## Continue after a file error

A missing file reports its error under its own heading; the files after it
are still returned, and the call exits 1 so the tool reports it as an error.

```mooncram
$ moonx "$READ" absent.txt note.txt
=== "absent.txt" ===
error reading file: "OSError(\"@fs.kind(): \\\"absent.txt\\\": No such file or directory\")"
=== "note.txt" ===
1 |whole file
<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
[1]
```

A directory is refused with the way to list it instead.

```mooncram
$ moonx "$READ" dir
=== "dir" ===
error reading file: "path is a directory; list it with mbtx (@fs.readdir/@shell.glob), then read specific files"
[1]
```

## Read filenames that look like selectors or options

A trailing `:number` is read as a line number, so a file actually named that
way needs `--literal`. This fixture uses Unix filename rules; Windows reserves
the colon, so it is not a portable literal-filename example.

```mooncram
$ printf 'kept' > log:12
```

```mooncram
$ moonx "$READ" log:12
=== "log" ===
error reading file: "OSError(\"@fs.kind(): \\\"log\\\": No such file or directory\")"
[1]
```

```mooncram
$ moonx "$READ" --literal log:12
=== "log:12" ===
1 |kept
<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
```

A name starting with `--` needs two separators: the first `--` ends `moonx`
option parsing, and the second is passed to `read.mbtx` to end its option parsing.

```mooncram
$ printf 'dash' > ./--weird
```

```mooncram
$ moonx "$READ" -- -- --weird
=== "--weird" ===
1 |dash
<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
```

## Limit output in UTF-8 bytes

`--max-output-bytes` bounds each file's body in UTF-8 bytes, gutters
included. A body that does not fit is marked `truncated=true`; request a
smaller range to continue. Truncation is a successful read, so there is no
`[1]` after the output.

Nine bytes fit the first line (`1 |first`) but not the next line's gutter:

```mooncram
$ moonx "$READ" --max-output-bytes 9 sample.mbt
=== "sample.mbt" ===
1 |first
<system>start_line=1 shown_lines=1 total_lines=4 truncated=true</system>
```

A budget can also cut a line short. Five bytes leave room for the gutter
(`1 |`) and `fi`, so `shown_lines=1` does not promise a complete line.
Cuts preserve UTF-8 character boundaries.

```mooncram
$ moonx "$READ" --max-output-bytes 5 sample.mbt
=== "sample.mbt" ===
1 |fi
<system>start_line=1 shown_lines=1 total_lines=4 truncated=true</system>
```

## Diagnose arguments and show help

Argument errors name what was wrong and exit 1 before any file is read.

```mooncram
$ moonx "$READ" sample.mbt:5:4
error: read expected path:start:end with end >= start (inclusive, 1-based)
[1]
```

```mooncram
$ moonx "$READ" --unknown
error: read unknown option; use --help or -- before a filename starting with --
[1]
```

```mooncram
$ moonx "$READ" --help
Usage: mbtx(filename="@builtin/read.mbtx", args=["path", "path:start", "path:start:end"])
Ranges are inclusive and 1-based. --max-output-bytes N sets each file's UTF-8 body budget (default 12000, maximum 50000). The batch is bounded to 40000 UTF-8 bytes; use smaller batches/ranges when truncated. --literal PATH reads a path without interpreting colon suffixes. -- ends option parsing. Relative paths use cwd (default workspace).
```
