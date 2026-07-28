# R6RS Test Corpus

This package contains MoonBit test cases migrated from the Racket R6RS test
suite. The generated MoonBit cases preserve the upstream corpus organization.

The `verify-r6rs-tests.rkt` script can compare the MoonBit test vectors with a
local Racket R6RS implementation:

```bash
racket verify-r6rs-tests.rkt
```

Use `--help` to see filtering and reporting options. Exact verification results
depend on the locally installed Racket version.

The original suite is available from the
[Racket R6RS repository](https://github.com/racket/r6rs).
