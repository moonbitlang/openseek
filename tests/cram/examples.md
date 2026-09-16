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
