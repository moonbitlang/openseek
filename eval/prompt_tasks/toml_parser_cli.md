Build a small MoonBit TOML parser library and native CLI in the current
workspace.

Requirements:

- Create a current MoonBit project using `moon.mod`, not `moon.mod.json`.
- Implement a TOML subset parser for:
  - comments beginning with `#`
  - blank lines and leading/trailing whitespace
  - bare keys and dotted keys
  - tables such as `[owner]` and nested tables such as `[database.settings]`
  - strings with `\"`, `\\`, `\n`, and `\t` escapes
  - integers, booleans, and arrays of those values
  - duplicate-key errors with a useful message
- Expose a library API that can parse TOML text into a deterministic JSON value.
- Add black-box tests for successful parsing and malformed input.
- Add a native CLI at `cmd/tomljson` that prints JSON for either:
  - a file path argument
  - `--stdin`, reading TOML from stdin
- Keep successful CLI stdout as valid JSON only.
- For invalid input, the CLI must not print a MoonBit panic/debug stack.

Validation expectations before finishing:

- Run `moon check`.
- Run targeted `moon test`.
- Run `moon info` and `moon fmt`.
- Run at least these CLI probes:
  - file input containing a nested table and array
  - stdin input containing dotted keys
  - invalid duplicate key input
- Finish only after reporting the validation commands and any remaining caveats.
