You are running a MoonBit coding-agent benchmark.

Workspace: {{WORKSPACE}}

Build a small MoonBit UTF-8 decoder / validator library and native CLI in that
workspace. This measures byte-level care and defensive handling of adversarial
input.

Requirements:

- Create a current MoonBit project using `moon.mod`, not `moon.mod.json`.
- Implement a strict UTF-8 decoder that turns a byte sequence into Unicode code
  points and rejects, as invalid:
  - continuation bytes without a valid leading byte,
  - truncated multi-byte sequences,
  - overlong encodings (e.g. `C0 AF` for `/`),
  - encodings of surrogate code points `U+D800`–`U+DFFF`,
  - code points above `U+10FFFF`.
- Add a native CLI at `cmd/utf8` with mode `decode`: read a hex string from
  **stdin** (an even number of hex digits, ASCII whitespace ignored), interpret
  the bytes as UTF-8, and print the decoded code points as space-separated
  `U+XXXX` tokens using uppercase hex, zero-padded to at least four digits (more
  when needed, e.g. `U+1F600`).
- Add black-box tests covering ASCII, multi-byte sequences, and each rejection
  category above.
- On invalid UTF-8, on odd-length input, or on non-hex input, the CLI must print
  a clean, single-line error to stderr containing the word `error`, then exit
  non-zero. A MoonBit panic, abort, or debug stack must never reach the output.

Validation expectations before finishing:

- Run `moon check --target native`.
- Run `moon test --target native`.
- Run `moon fmt`.
- Run at least these CLI probes (stdin hex → expected):
  - `f09f9880` → contains `U+1F600` (a 4-byte sequence).
  - `48656C6C6F` → contains `U+0048` (ASCII "Hello").
  - `c0af` → an error (overlong).
  - `f09f98` → an error (truncated).
  - `eda080` → an error (surrogate).
- Finish only after reporting the validation commands you ran and any remaining
  caveats.
