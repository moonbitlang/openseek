# OpenSeek Edit CLI

The `edit` agent tool as a standalone program, so a **program tool call** (an
`mbtx` snippet) can compose edits itself instead of the model emitting one tool
call per change. The model can then derive edits from something it just
computed — `moon check` output, a grep result — and apply them in a loop, inside
a single turn.

This package is deliberately thin. It builds `agent_tool/edit`'s definition and
runs *that* package's own executor, so the decode, the exact-match discipline,
the parse gate, and the response text are the same ones the in-process tool
produces. There is no second implementation of edit to drift.

```bash
edit '{"path":"src/a.mbt","old_string":"one","new_string":"two","start_line":12}'
echo "$payload" | edit          # or from stdin, for a large payload
```

Exit status is 0 when the tool responded normally and 1 when it reported an
error, so a snippet can branch on the result instead of parsing the message. The
tool's own text goes to stdout either way.

## Confinement Comes From The Environment

The caller writes the JSON, so the JSON cannot be what decides where writes may
land — otherwise a snippet could widen its own reach just by asking. The bound
comes from the environment instead, and the payload has no say in it:

| Variable | Meaning |
| --- | --- |
| `OPENSEEK_EDIT_ROOT` | Workspace root. When set, every write is confined to it by a `write_scope`. When unset, the program runs unconfined against the working directory — the standalone, non-agent mode. |
| `OPENSEEK_EDIT_ALLOWED_PATHS` | Newline-separated paths that narrow that scope further, matching a worker subagent's `allowed_paths`. Ignored without a root, since there is nothing to resolve against. |

A malformed allowlist fails the run rather than silently widening to the whole
root: a confinement that cannot be built is not a confinement. The scope
resolves symlinks and `..` before deciding, so neither can smuggle a write out.

## Who May Spawn This

The environment is the confinement, so whoever spawns this program decides its
bound. That is sound when the spawner is the engine, which sets the variables
itself. It is **not** sound when the spawner is a model-authored `mbtx` snippet:
`@process.run` takes `extra_env` and `inherit_env`, so a snippet can start this
program with any environment it likes, including none.

That is why this binary is **not** on the mbtx spawn allowlist. A snippet today
cannot write the workspace at all — moonrun's `fs` rules grant it only its temp
directory and a read-only role's scratch lab, deliberately, so that a snippet
cannot route around `remove`'s provenance check. Admitting an editor that takes
its scope from a caller-supplied environment would hand back exactly that reach.

Wiring this up for program tool calls therefore needs a confinement the caller
cannot choose. The workable shape is discovery rather than instruction: the
engine writes the policy inside the workspace, and this program finds it by
walking up from the file it is about to modify. A snippet cannot plant a
competing policy there, because it cannot write there.

## What This Does Not Carry

Provenance. The engine's `FileStateMap` records which files the agent created or
modified this session, and `remove` will only delete a file it can prove the
agent created and that is byte-identical to what was written. That map is an
in-memory handle inside the engine process, so edits made here are invisible to
it.

The effect is fail-closed and intentional: `remove` refuses to delete a file
that only this program touched, because it cannot prove the provenance. Sharing
the record across both paths is a separate piece of work, and it is what would
let `remove` act on programmatic edits.

## Tests

[`tests/cram/edit.md`](../../tests/cram/edit.md) is executable documentation of
this command line: a successful edit, stdin input, a failed match, the parse
gate, and the environment confinement. It runs offline.

```bash
moon cram test tests/cram
```
