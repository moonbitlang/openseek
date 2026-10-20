# mbtx/internal/decode

Argument decoding for the `mbtx` tool. `decode(Json) -> MbtxInput`
reads `source` (a `.mbtx` program), `filename` (an existing script), or both
(save and run a writable script), represented by the `Program` enum. Namespaced
filenames cannot accompany source. `args` is an optional array of strings,
defaulting to `[]`; null and non-string elements are rejected. It also reads
the optional `target` backend (`wasm`, `wasm-gc`, `js`, or `llvm`), defaulting
to `wasm` when missing or null. `native` remains unsupported. Accepting a
non-wasm backend here only validates its name: execution requests approval
automatically and refuses the run when no approval channel is available. It
also reads `cwd`, `warning`, and `escalated`. It names the offending field on
failure so the error fed back to the model says exactly what to fix. The removed
`run_in_background` field is rejected explicitly with migration guidance:
handoff is automatic when the caller wires a job runtime.
