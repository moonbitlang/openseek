You are running a MoonBit coding-agent benchmark.

Workspace: {{WORKSPACE}}

Build a small MoonBit URI parser / normalizer / resolver library and native CLI
in that workspace. This measures fidelity to a compact state-machine
specification (RFC 3986) with many corner cases.

Requirements:

- Create a current MoonBit project using `moon.mod`, not `moon.mod.json`.
- Implement a standards-informed URI parser splitting scheme, authority
  (userinfo, host, port), path, query, and fragment.
- Implement `normalize`, applying at least:
  - lowercase the scheme and the host,
  - remove dot-segments (`.` and `..`) from the path per RFC 3986 §5.2.4,
  - uppercase the hex digits of percent-encoded octets (`%3a` → `%3A`) and
    decode percent-encoded unreserved characters,
  - drop a default port (`:80` for `http`, `:443` for `https`).
- Implement `resolve`, computing the target of a relative reference against a
  base URI per RFC 3986 §5.2 (the reference-resolution algorithm).
- Add black-box tests, including the normal examples from RFC 3986 §5.4.1.
- Add a native CLI at `cmd/urinorm`. The input URI (or relative reference) is
  read from **stdin**. The first argument selects the mode:
  - `normalize` — print the normalized form of the stdin URI.
  - `resolve <base>` — print the stdin relative reference resolved against
    `<base>`.
- Successful CLI stdout must be the single resulting URI only.
- On invalid input the CLI must print a clean, single-line error to stderr
  containing the word `error`, then exit non-zero. A MoonBit panic, abort, or
  debug stack must never reach the output.

Validation expectations before finishing:

- Run `moon check --target native`.
- Run `moon test --target native`.
- Run `moon fmt`.
- Run at least these CLI probes:
  - `normalize` of `http://a/b/c/../g` → `http://a/b/g` (dot-segments).
  - `normalize` of `HTTP://Example.COM/` → `http://example.com/` (case).
  - `resolve http://a/b/c/d;p?q` on the reference `../../g` → `http://a/g`.
  - an unparseable input (must error, not panic).
- Finish only after reporting the validation commands you ran and any remaining
  caveats.
