# Verified `@builtin/read.mbtx` Output Contract

These examples are executed by `moon cram test tests/cram`. They run the
bundled read workflow, `share/workflow/read.mbtx`, directly through `moon run`
from a scratch directory, the way the `mbtx` tool runs it for the agent (the
tool adds only its sandbox policy and its own output cap). The script's
output is a contract two other parts of the engine consume: the system prompt
tells the model what the footers mean, and the desktop transcript recognizes
the headings and gutters to highlight MoonBit source. What is pinned here is
that text, byte for byte.

Every example passes `--target-dir _build`, which lands in the scratch
directory: without it `moon run` would leave a `_build` tree beside the script
under `share/`, and that tree once made its way into the generated system
prompt's outline of `share/`. Each block runs one command; the scratch
directory persists from block to block, so the fixtures below serve every
example.

## Fixtures

A file that ends in a newline has a final empty line, as the footers below
count it.

```mooncram
$ printf 'first\nselected\nlast\n' > sample.mbt && printf 'whole file' > note.txt && : > empty.txt && mkdir dir
```

## A Whole File

Every file gets a JSON-quoted heading, a numbered body, and a `<system>`
footer.

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- sample.mbt
=== "sample.mbt" ===
1 |first
2 |selected
3 |last
4 |
<system>start_line=1 shown_lines=4 total_lines=4 truncated=false</system>
```

## A Range, And A Tail

Selectors are `path`, `path:start`, or `path:start:end`; lines are 1-based
and both ends are included.

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- sample.mbt:2:3
=== "sample.mbt" ===
2 |selected
3 |last
<system>start_line=2 shown_lines=2 total_lines=4 truncated=false</system>
```

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- sample.mbt:3
=== "sample.mbt" ===
3 |last
4 |
<system>start_line=3 shown_lines=2 total_lines=4 truncated=false</system>
```

## Past The End, And An Empty File

A range beyond the end is not an error: the footer reports what the file
holds. An empty file says so explicitly. Several selectors in one call come
back in order, each under its own heading.

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- sample.mbt:10:20 empty.txt
=== "sample.mbt" ===
<system>start_line=10 shown_lines=0 total_lines=4 truncated=false</system>
=== "empty.txt" ===
<system>start_line=1 shown_lines=0 total_lines=0 truncated=false note=empty file</system>
```

## A Batch Survives One Bad File

A missing file reports its error under its own heading; the files after it
are still returned, and the call exits 1 so the tool reports it as an error.

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- absent.txt note.txt
=== "absent.txt" ===
error reading file: "OSError(\"@fs.kind(): \\\"absent.txt\\\": No such file or directory\")"
=== "note.txt" ===
1 |whole file
<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
[1]
```

A directory is refused with the way to list it instead.

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- dir
=== "dir" ===
error reading file: "path is a directory; list it with mbtx (@fs.readdir/@shell.glob), then read specific files"
[1]
```

## Names That Look Like Selectors

A trailing `:number` is read as a line number, so a file actually named that
way needs `--literal`.

```mooncram
$ printf 'kept' > log:12 && moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- log:12
=== "log" ===
error reading file: "OSError(\"@fs.kind(): \\\"log\\\": No such file or directory\")"
[1]
```

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- --literal log:12
=== "log:12" ===
1 |kept
<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
```

A name starting with `--` needs `--` first.

```mooncram
$ printf 'dash' > ./--weird && moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- -- --weird
=== "--weird" ===
1 |dash
<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
```

## The Body Budget

`--max-output-bytes` bounds each file's body in UTF-8 bytes, gutters
included. A body that does not fit is cut at a line and marked `truncated`,
which is the model's cue to ask for a narrower range.

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- --max-output-bytes 9 sample.mbt
=== "sample.mbt" ===
1 |first
<system>start_line=1 shown_lines=1 total_lines=4 truncated=true</system>
```

## Bad Arguments And Help

Argument errors name what was wrong and exit 1 before any file is read.

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- sample.mbt:5:4
error: read expected path:start:end with end >= start (inclusive, 1-based)
[1]
```

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- --unknown
error: read unknown option; use --help or -- before a filename starting with --
[1]
```

```mooncram
$ moon run -q "$TESTDIR/../../share/workflow/read.mbtx" --target-dir _build -- --help
Usage: mbtx(filename="@builtin/read.mbtx", args=["path", "path:start", "path:start:end"])
Ranges are inclusive and 1-based. --max-output-bytes N sets each file's UTF-8 body budget (default 12000, maximum 50000). The batch is bounded to 40000 UTF-8 bytes; use smaller batches/ranges when truncated. --literal PATH reads a path without interpreting colon suffixes. -- ends option parsing. Relative paths use cwd (default workspace).
```
