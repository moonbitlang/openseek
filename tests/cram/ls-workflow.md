# Listing files with `ls.mbtx`

This page is both a usage guide and an executable test of
[`ls.mbtx`](../../share/workflow/ls.mbtx). Each `mooncram` block shows a
shell command after `$`, followed by its expected output. `[1]` means the
command must exit with status 1; without it, success is expected.

Run this page from the repository root:

```sh
moon cram test tests/cram/ls-workflow.md --shell bash
```

In OpenSeek, the equivalent of the first listing below is:

```json
{"filename":"@builtin/ls.mbtx","args":["engine"]}
```

The [mbtx package test](../../agent_tool/mbtx/ls_workflow_test.mbt) runs the
embedded copy through the tool and its sandbox. See
[Writing cram documentation](README.md) for how these pages work.

## Set up the examples

```mooncram
$ LS="$TESTDIR/../../share/workflow/ls.mbtx"
```

```mooncram
$ READ="$TESTDIR/../../share/workflow/read.mbtx"
```

A small project: sources under `engine/`, SQL fixtures under `tests/`, a
binary file, an empty file, and a `_build/` directory of build output.

```mooncram
$ mkdir -p engine/parser tests/m01 tests/m02 _build/native
```

```mooncram
$ printf 'fn main {\n  ()\n}\n' > engine/main.mbt
```

```mooncram
$ printf 'let x = 1\nlet y = 2' > engine/lexer.mbt
```

```mooncram
$ printf 'enum Token {}\n' > engine/parser/token.mbt
```

```mooncram
$ printf 'select 1;\n' > tests/m01/basic.sql
```

```mooncram
$ printf 'select 1;\nselect 2;\n' > tests/m02/join.sql
```

```mooncram
$ printf 'MZ\000\001' > logo.bin
```

```mooncram
$ touch empty.txt _build/native/main.mbt
```

## List a directory

Each line is `COUNT PATH`, sorted. `COUNT` is the file's line count, like
`wc -l`, except that a last line without a newline counts too (`lexer.mbt`
has two). `-` marks a directory, whose path ends in `/`. Paths include the
directory you named, so any line can be passed straight to
`@builtin/read.mbtx PATH:start:end`.

```mooncram
$ moonx "$LS" engine
2 engine/lexer.mbt
3 engine/main.mbt
- engine/parser/
```

With no arguments the working directory is listed. Binary files (a NUL byte
near the start) and files over 4 MB show a byte size marked `B` instead of a
line count. `_build`, `.git`, `.mooncakes`, `node_modules` and `target` are
left out, and a note says which were there.

```mooncram
$ moonx "$LS"
 0 empty.txt
 - engine/
4B logo.bin
 - tests/
<system>skipped=_build note=pass --all to list them</system>
```

## List what a glob matches

Globs go where paths go, as in a shell: `*` and `?` match within one path
segment. Several paths and globs can share one call.

```mooncram
$ moonx "$LS" 'engine/*.mbt' 'tests/m0?/*.sql'
2 engine/lexer.mbt
3 engine/main.mbt
1 tests/m01/basic.sql
2 tests/m02/join.sql
```

`**` spans any number of directories, including none. Matches inside the
skipped directories are dropped unless the pattern names them.

```mooncram
$ moonx "$LS" '**/*.mbt'
2 engine/lexer.mbt
3 engine/main.mbt
1 engine/parser/token.mbt
<system>skipped=_build note=pass --all to list them</system>
```

```mooncram
$ moonx "$LS" '_build/**/*.mbt'
0 _build/native/main.mbt
```

A glob that matches nothing is an answer, not a failure:

```mooncram
$ moonx "$LS" 'engine/*.rs'
<system>no matches for "engine/*.rs"</system>
```

## Recurse

`-R` lists the whole tree, each directory followed by its contents. The
skipped directories stay out; `--all` includes them.

```mooncram
$ moonx "$LS" -R
 0 empty.txt
 - engine/
 2 engine/lexer.mbt
 3 engine/main.mbt
 - engine/parser/
 1 engine/parser/token.mbt
4B logo.bin
 - tests/
 - tests/m01/
 1 tests/m01/basic.sql
 - tests/m02/
 2 tests/m02/join.sql
<system>skipped=_build note=pass --all to list them</system>
```

```mooncram
$ moonx "$LS" -R --all _build
- _build/native/
0 _build/native/main.mbt
```

`--depth N` recurses N levels; `--depth 1` is a plain listing.

```mooncram
$ moonx "$LS" --depth 2 tests
- tests/m01/
1 tests/m01/basic.sql
- tests/m02/
2 tests/m02/join.sql
```

`-g GLOB` filters the entries as `@builtin/rg.mbtx -g` does: a pattern
without `/` matches names, one with `/` matches the path below the listed
directory, and `!GLOB` excludes (pruning a directory it names). A positive
filter keeps only matching files.

```mooncram
$ moonx "$LS" -R -g '*.sql'
1 tests/m01/basic.sql
2 tests/m02/join.sql
<system>skipped=_build note=pass --all to list them</system>
```

```mooncram
$ moonx "$LS" -R -g '!parser' -g '!tests'
 0 empty.txt
 - engine/
 2 engine/lexer.mbt
 3 engine/main.mbt
4B logo.bin
<system>skipped=_build note=pass --all to list them</system>
```

## Missing paths

A path that does not exist is an error naming it. The other arguments are
still listed, and the call exits 1.

```mooncram
$ moonx "$LS" absent.txt engine/main.mbt
error: no such file or directory: "absent.txt"
3 engine/main.mbt
[1]
```

## Bounded output

Output stops below 40000 UTF-8 bytes, under the mbtx transport limit. The
footer gives how many entries were shown out of the total; narrow the
listing to see the rest.

```mooncram
$ mkdir many && for i in $(seq 1 600); do : > "many/$(printf 'entry-%04d-with-a-long-descriptive-name-to-fill-the-output-budget.txt' "$i")"; done
```

```mooncram
$ moonx "$LS" many | tail -n 1
<system>truncated=true shown_entries=506 total_entries=600 note=narrow the listing with a glob, -g GLOB or --depth N</system>
```

```mooncram
$ moonx "$LS" many | wc -c | tr -d ' '
39088
```

## Reading a directory points here

`@builtin/read.mbtx` refuses a directory and names this script:

```mooncram
$ moonx "$READ" engine
=== "engine" ===
error reading file: "path is a directory; list it with @builtin/ls.mbtx, then read specific files"
[1]
```

## Diagnose arguments and show help

```mooncram
$ moonx "$LS" --depth 0
error: ls --depth expects a positive integer
[1]
```

```mooncram
$ moonx "$LS" -x
error: ls unknown option -x; use --help, or -- before a path starting with -
[1]
```

```mooncram
$ moonx "$LS" --help
Usage: mbtx(filename="@builtin/ls.mbtx", args=["PATH or GLOB", ...])
Lists paths; no args lists `.`. A directory lists its entries; a glob such
as `src/*.mbt`, `tests/m0?/*.sql` or `src/**/*.mbt` lists what it matches
(`*` and `?` stay inside one path segment, `**` spans directories, hidden
names need an explicit `.`).
Each line is `COUNT PATH`, sorted, with PATH ready for
`@builtin/read.mbtx PATH:start:end`. COUNT is the file's line count (like
wc -l; a last line without a newline counts too); `NB` is a size in bytes,
for binary files and files over 4 MB; `-` marks a directory, whose PATH
ends in `/`.
-R recurses; --depth N recurses N levels (1 lists entries only). _build,
.git, .mooncakes, node_modules and target are skipped inside listings;
--all includes them. -g GLOB keeps matching entries, as in rg: a GLOB
without `/` matches names, `!GLOB` excludes, and it repeats. -a and -l are
accepted and ignored: hidden entries and counts are always shown.
Output is bounded to 40000 UTF-8 bytes; narrow the listing when truncated.
A glob that matches nothing exits 0 with a note; a missing path is an
error. -- ends options. Relative paths use cwd (default workspace).
```
