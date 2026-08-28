# mbtx/internal/decode

Argument decoding for the `mbtx` tool. `decode(Json) -> MbtxInput`
reads the required `source` string (a `.mbtx` program) and the optional
`target` backend (default `native`, validated against
`native`/`wasm`/`wasm-gc`/`js`/`llvm`), naming the offending field on failure so
the error fed back to the model says exactly what to fix.
