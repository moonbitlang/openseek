# Looking up APIs with `doc.mbtx`

This page is both a usage guide and an executable test of
[`doc.mbtx`](../../share/workflow/doc.mbtx), which runs `moon ide doc` with
its arguments as queries. Each `mooncram` block shows a shell command after
`$`, followed by its expected standard output. `[1]` means the command must
exit with status 1; without it, success is expected.

Run this page from the repository root:

```sh
moon cram test tests/cram/doc-workflow.md --shell bash
```

In OpenSeek, a lookup is one call, with one query per argument:

```json
{"filename":"@builtin/doc.mbtx","args":["@moonbitlang/core/async/shell","StringView::split"]}
```

These tests run the script directly with `moonx` against a small temporary
module, so the expected output does not depend on the toolchain's own
documentation. `--no-registry` is passed through to `moon ide doc` to keep
the examples offline.

## Set up the examples

As in the [read guide](read-workflow.md), a path variable keeps each example
short; Cram preserves it between blocks.

```mooncram
$ DOC="$TESTDIR/../../share/workflow/doc.mbtx"
```

The module has one documented function:

```mooncram
$ cat > moon.mod <<'EOF'
> name = "example/doc_docs"
> EOF
```

```mooncram
$ touch moon.pkg
```

```mooncram
$ cat > answer.mbt <<'EOF'
> ///|
> /// The answer to everything.
> pub fn answer() -> Int {
>   42
> }
> EOF
```

## Usage

No arguments, or `--help`, print the usage text without running Moon.
`-h` reaches `moon ide doc` and prints its own flag summary instead.

```mooncram
$ moonx "$DOC" --help
Usage: mbtx(filename="@builtin/doc.mbtx", args=["QUERY", ...])
Runs `moon ide doc` with these arguments, unchanged: each one is a query
for exported APIs and their documentation in the current module, its
dependencies, moonbitlang/core, and registry indexes.
Queries: "StringView::split" (method), "@json.parse" (package function),
"@json" or "@moonbitlang/core/async/shell" (whole package), "String"
(type), and `*` globs anywhere ("String::*rev*", "*parse*"). Batch
several queries in one call; each miss is listed and the others return.
Output is bounded to 40000 UTF-8 bytes; narrow the query when truncated.
No match exits 0 with a note. cwd (default workspace) selects the module.
args=["-h"] prints moon ide doc's own flag summary.
```

## Look up a symbol or a package

A symbol query prints its signature and documentation. A package query lists
the package's exported API.

```mooncram
$ moonx "$DOC" --no-registry '@doc_docs.answer'
package "example/doc_docs" // example/doc_docs@local
pub fn answer() -> Int32
  The answer to everything.
```

```mooncram
$ moonx "$DOC" --no-registry '@doc_docs'
package "example/doc_docs" // example/doc_docs@local

pub fn answer() -> Int32
```

## Misses are answers

`moon ide doc` exits 1 whenever any query finds nothing, even when others
match. The script keeps the hits, names every miss in a closing note, and
exits 0, so a miss does not read as a failed command.

```mooncram
$ moonx "$DOC" --no-registry '@doc_docs.answer' 'answer_typo'
package "example/doc_docs" // example/doc_docs@local
pub fn answer() -> Int32
  The answer to everything.

No results found for query: 'answer_typo'
<system>no matches for "answer_typo"; retry once with a bare glob such as "*name*" or list the package ("@moonbitlang/core/async/fs") and read the real names</system>
```

An unknown package is reported the same way:

```mooncram
$ moonx "$DOC" --no-registry '@nosuchpkg'
package nosuchpkg not found in example/doc_docs
<system>no matches for "@nosuchpkg"; retry once with a bare glob such as "*name*" or list the package ("@moonbitlang/core/async/fs") and read the real names</system>
```

## Other failures keep Moon's exit status

Anything else that makes `moon ide doc` fail, such as an unknown flag, is
passed on unchanged; Moon's message goes to stderr.

```mooncram
$ moonx "$DOC" --bogus
[1]
```
