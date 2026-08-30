# mbtx/internal/decode

Argument decoding for the `mbtx` tool. `decode(Json) -> MbtxInput`
reads the required `source` string (a `.mbtx` program) and the optional
`target` backend (default `wasm`, validated against
`wasm`/`wasm-gc`/`js`/`llvm`), `cwd`, `warning`, and `escalated` fields. It names
the offending field on failure so the error fed back to the model says exactly
what to fix. The removed `run_in_background` field is rejected explicitly with
migration guidance: handoff is automatic when the caller wires a job runtime.
