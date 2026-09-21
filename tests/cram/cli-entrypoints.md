# Root and legacy CLI entry points

Run with `moon cram test tests/cram/cli-entrypoints.md --shell bash`. Both
packages are built as native executables. They share command behavior; only
the legacy package adds a single deprecation warning on stderr.

Compare help output, JSON stdout, and invalid-argument exit status using the
explicit executable paths. Warning output must never enter stdout, and a
legacy invocation must emit exactly one warning before any command diagnostic.

```mooncram
$ sh <<'SH'
> set -eu
> root="$TESTDIR/../../_build/native/debug/build/moonbitlang/openseek/openseek.exe"
> legacy="$TESTDIR/../../_build/native/debug/build/moonbitlang/openseek/cmd/openseek/openseek.exe"
> printf '%s\n' 'Warning: moonbitlang/openseek/cmd/openseek is deprecated; use moonx moonbitlang/openseek instead.' >warning.err
> "$root" --help >root-help.out 2>root-help.err
> "$legacy" --help >legacy-help.out 2>legacy-help.err
> cmp root-help.out legacy-help.out
> test ! -s root-help.err
> cmp warning.err legacy-help.err
> echo 'help: identical stdout, legacy warning only'
> mkdir empty-sessions
> "$root" sessions list --format=json --session-root empty-sessions >root-json.out 2>root-json.err
> "$legacy" sessions list --format=json --session-root empty-sessions >legacy-json.out 2>legacy-json.err
> cmp root-json.out legacy-json.out
> test "$(cat root-json.out)" = '[]'
> test ! -s root-json.err
> cmp warning.err legacy-json.err
> echo 'JSON: identical stdout, legacy warning only'
> if "$root" unknown-command >root-error.out 2>root-error.err; then exit 1; else test "$?" -eq 1; fi
> if "$legacy" unknown-command >legacy-error.out 2>legacy-error.err; then exit 1; else test "$?" -eq 1; fi
> test ! -s root-error.out
> cmp root-error.out legacy-error.out
> head -n 1 legacy-error.err | cmp warning.err -
> tail -n +2 legacy-error.err | cmp root-error.err -
> echo 'invalid arguments: identical error and exit status 1'
> SH
help: identical stdout, legacy warning only
JSON: identical stdout, legacy warning only
invalid arguments: identical error and exit status 1
```
