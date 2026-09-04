# Verified OpenSeek Edit CLI Documentation

These examples are executed by `moon cram test tests/cram`. The Moon wrapper
builds the native package at `cmd/edit` and exposes the executable on `PATH` as
`edit.exe`.

`edit.exe` is the `edit` agent tool as a standalone program, so a program tool
call (an `mbtx` snippet) can compose edits itself instead of the model emitting
one tool call per change. It is a thin main over `agent_tool/edit` and runs that
package's own executor, so the decode, the parse gate, and the response text are
the same ones the in-process tool produces.

Every command here is offline: it only reads and writes files in its own
scratch directory and never contacts a model.

## An Edit Is One JSON Object

The arguments are the tool's own JSON schema — `path`, `old_string`,
`new_string`, and `start_line` are required. A successful edit reports what it
replaced and exits zero.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d); cd "$d"
> printf 'one\ntwo\n' > a.txt
> edit.exe '{"path":"a.txt","old_string":"two","new_string":"THREE","start_line":2}'
> cat a.txt
> cd /; rm -rf "$d"
> EOF
ok: replaced 1 occurrence(s) at line 2 in a.txt
one
THREE
```

## Arguments May Come From Stdin

A large payload does not have to fit on the command line: with no argument, the
program reads the JSON object from stdin instead.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d); cd "$d"
> printf 'one\n' > a.txt
> echo '{"path":"a.txt","old_string":"one","new_string":"two","start_line":1}' | edit.exe
> cd /; rm -rf "$d"
> EOF
ok: replaced 1 occurrence(s) at line 1 in a.txt
```

## A Failed Edit Exits Non-Zero

The exact `old_string` is what proves the file still holds what the caller
expects. When it does not match, nothing is written and the exit status is 1, so
a snippet can branch on the result rather than parsing the message.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d); cd "$d"
> printf 'one\n' > a.txt
> if edit.exe '{"path":"a.txt","old_string":"zzz","new_string":"x","start_line":1}' > out 2>&1; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' out
> cat a.txt
> cd /; rm -rf "$d"
> EOF
exit-non-zero
error editing a.txt: old_string not found from line 1
one
```

## The Parse Gate Applies Here Too

Because this is the same executor, an edit that would introduce new parse errors
into a MoonBit file is refused and the file is left alone — the gate is not
something the in-process tool adds on top.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d); cd "$d"
> printf 'fn main {\n  println("one")\n}\n' > a.mbt
> edit.exe '{"path":"a.mbt","old_string":"fn main {","new_string":"fn main {{{","start_line":1}' 2>&1 | sed -n '1p'
> sed -n '1p' a.mbt
> cd /; rm -rf "$d"
> EOF
rejected: the edit would introduce 1 new parse error(s) in a.mbt, so the file was NOT modified.
fn main {
```

## Confinement Comes From The Environment, Not The Payload

The caller writes the JSON, so the JSON cannot be what decides where writes may
land. `OPENSEEK_EDIT_ROOT` bounds every write to one root and
`OPENSEEK_EDIT_ALLOWED_PATHS` narrows it further, matching a worker subagent's
`allowed_paths`. A path inside the root but outside the allowlist is refused.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d); cd "$d"
> mkdir -p allowed other
> printf 'one\n' > allowed/a.txt
> printf 'one\n' > other/b.txt
> export OPENSEEK_EDIT_ROOT=. OPENSEEK_EDIT_ALLOWED_PATHS=allowed
> edit.exe '{"path":"allowed/a.txt","old_string":"one","new_string":"two","start_line":1}'
> edit.exe '{"path":"other/b.txt","old_string":"one","new_string":"pwned","start_line":1}' 2>&1 | sed -n '1p'
> cat other/b.txt
> cd /; rm -rf "$d"
> EOF
ok: replaced 1 occurrence(s) at line 1 in allowed/a.txt
error editing other/b.txt: write blocked: path is outside allowed_paths (allowed)
one
```

Leaving the root escapes nothing either: the scope resolves symlinks and `..`
before deciding, so the write is refused rather than followed.

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d); cd "$d"
> mkdir -p work
> cd work
> OPENSEEK_EDIT_ROOT=. edit.exe '{"path":"../escape.txt","old_string":"","new_string":"x","start_line":1}' 2>&1 | sed -n '1p' | sed 's|/private||; s|'"$d"'|<tmp>|'
> ls "$d"
> cd /; rm -rf "$d"
> EOF
error editing ../escape.txt: write blocked: path resolves outside the writable root <tmp>/work (through a symlink or ..)
work
```

## Malformed Input Is Reported, Not Guessed

```mooncram
$ sh <<'EOF'
> d=$(mktemp -d); cd "$d"
> if edit.exe 'not json' > out 2>&1; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' out
> if edit.exe '{"path":"a.txt"}' > out 2>&1; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' out
> cd /; rm -rf "$d"
> EOF
exit-non-zero
error: Invalid character 'o' at line 1, column 1
exit-non-zero
error: edit requires arguments.old_string
```
