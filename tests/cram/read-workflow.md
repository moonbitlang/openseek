# Reading files with `read.mbtx`

This page is both a usage guide and an executable test of
[`read.mbtx`](../../share/workflow/read.mbtx). Each `mooncram` block invokes
the real script after `$`, followed by its expected output. `[1]` means the
command must exit with status 1; without it, success is expected.

Run this page from the repository root:

```sh
moon testcli test tests/cram/read-workflow.md
```

These transcripts assume Unix filesystem behavior: the `log:12` fixture is not
an ordinary Windows filename, and OS error text can differ. CI runs on Linux.

In OpenSeek, the equivalent of the first example below is:

```json
{"filename":"@builtin/read.mbtx","args":["sample.txt"]}
```

Testcli builds and runs the actual script and compares its output and exit status.
The [mbtx package tests](../../agent_tool/mbtx/read_workflow_test.mbt)
cover execution through the tool, including sandbox and output-limit behavior.
See [Writing CLI documentation tests](README.md) to add examples for another script.

## Set up the examples

The [read fixtures](fixtures/read/) are checked-in, read-only inputs:
`sample.txt` contains `first`, `selected`, and `last`, with a trailing newline;
`note.txt` contains `whole file` without a newline; `empty.txt` is empty;
`dir` is a directory; and `--weird` contains `dash`.

Each block uses `#cwd` to read those files directly. Only the Unix-specific
literal-colon case creates a temporary file, so Windows checkouts do not need
to store a filename containing `:`.

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
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx sample.txt
=== "sample.txt" ===
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
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx sample.txt:2:3
=== "sample.txt" ===
2 |selected
3 |last
<system>start_line=2 shown_lines=2 total_lines=4 truncated=false</system>
```

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx sample.txt:3
=== "sample.txt" ===
3 |last
4 |
<system>start_line=3 shown_lines=2 total_lines=4 truncated=false</system>
```

## Read several files in one call

One call takes any number of selectors and returns them in the order given,
each under its own heading with its own footer. Selectors are independent, so
a range on one file does not affect the next. Batch the paths you already know
into a single call rather than calling once per file.

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx sample.txt:2:3 note.txt
=== "sample.txt" ===
2 |selected
3 |last
<system>start_line=2 shown_lines=2 total_lines=4 truncated=false</system>
=== "note.txt" ===
1 |whole file
<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
```

The same path may appear more than once, which is how two distant regions of
one file arrive together:

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx sample.txt:1:1 sample.txt:3
=== "sample.txt" ===
1 |first
<system>start_line=1 shown_lines=1 total_lines=4 truncated=false</system>
=== "sample.txt" ===
3 |last
4 |
<system>start_line=3 shown_lines=2 total_lines=4 truncated=false</system>
```

## Read past EOF or read an empty file

A range beyond the end is not an error: the footer reports what the file
holds. An empty file says so explicitly.

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx sample.txt:10:20 empty.txt
=== "sample.txt" ===
<system>start_line=10 shown_lines=0 total_lines=4 truncated=false</system>
=== "empty.txt" ===
<system>start_line=1 shown_lines=0 total_lines=0 truncated=false note=empty file</system>
```

## Continue after a file error

A missing file reports its error under its own heading; the files after it
are still returned, and the call exits 1 so the tool reports it as an error.

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx absent.txt note.txt
=== "absent.txt" ===
error reading file: "@fs.kind(): \"absent.txt\": No such file or directory"
=== "note.txt" ===
1 |whole file
<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
[1]
```

A directory is refused with the way to list it instead.

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx dir
=== "dir" ===
error reading file: "path is a directory; list it with mbtx (@fs.readdir/@shell.glob), then read specific files"
[1]
```

## Read filenames that look like selectors or options

A trailing `:number` is read as a line number, so a file actually named that
way needs `--literal`. This fixture uses Unix filename rules; Windows reserves
the colon, so it is not a portable literal-filename example.

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx log:12
=== "log" ===
error reading file: "@fs.kind(): \"log\": No such file or directory"
[1]
```

```mooncram
$ moonx fixtures/read-literal-name.mbtx
=== "log:12" ===
1 |kept
<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
exit=0
```

A name starting with `--` needs a preceding `--` separator. This separator ends option parsing in `read.mbtx`.

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx -- --weird
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
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx --max-output-bytes 9 sample.txt
=== "sample.txt" ===
1 |first
<system>start_line=1 shown_lines=1 total_lines=4 truncated=true</system>
```

A budget can also cut a line short. Five bytes leave room for the gutter
(`1 |`) and `fi`, so `shown_lines=1` does not promise a complete line.
Cuts preserve UTF-8 character boundaries.

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx --max-output-bytes 5 sample.txt
=== "sample.txt" ===
1 |fi
<system>start_line=1 shown_lines=1 total_lines=4 truncated=true</system>
```

## Diagnose arguments and show help

Argument errors name what was wrong and exit 1 before any file is read.

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx sample.txt:5:4
error: read expected path:start:end with end >= start (inclusive, 1-based)
[1]
```

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx --unknown
error: read unknown option; use --help or -- before a filename starting with --
[1]
```

```mooncram
#cwd(fixtures/read)
$ moonx ../../../../share/workflow/read.mbtx --help
Usage: mbtx(filename="@builtin/read.mbtx", args=["path", "path:start", "path:start:end"])
Ranges are inclusive and 1-based. --max-output-bytes N sets each file's UTF-8 body budget (default 12000, maximum 50000). The batch is bounded to 40000 UTF-8 bytes; use smaller batches/ranges when truncated. --literal PATH reads a path without interpreting colon suffixes. -- ends option parsing. Relative paths use cwd (default workspace).
```
