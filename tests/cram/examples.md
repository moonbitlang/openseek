# Running the verified examples

The language examples under `share/examples/` are ordinary scripts: each
runs to completion and asserts what its comments teach. This page runs them,
so their output is pinned and a toolchain change that breaks one fails here.
The PTC examples need a host and are run by `agent_tool/mbtx/examples_test.mbt`
instead. Run this page from the repository root:

```sh
moon cram test tests/cram/examples.md --shell bash
```

```mooncram
$ moonx "$TESTDIR/../../share/examples/checked_errors.mbtx"
checked errors: ok
```

```mooncram
$ moonx "$TESTDIR/../../share/examples/syntax_basics.mbtx"
syntax: ok
```

```mooncram
$ moonx "$TESTDIR/../../share/examples/strings_and_views.mbtx"
strings and views: ok
```

The CLI example counts what it reads; here stdin is six bytes:

```mooncram
$ printf 'hello\n' | moonx "$TESTDIR/../../share/examples/cli_count_input.mbtx" --stdin
6
```

The greeting example is what the prompt promises about `args`: an option
declared with a default, and the same script reading it from the caller.

```mooncram
$ moonx "$TESTDIR/../../share/examples/cli_greet.mbtx"
Hello, world!
```

```mooncram
$ moonx "$TESTDIR/../../share/examples/cli_greet.mbtx" --name "Ada Lovelace"
Hello, Ada Lovelace!
```
