You are running a MoonBit coding-agent benchmark.

Workspace: {{WORKSPACE}}

Build a small MoonBit arithmetic expression parser and evaluator library and
native CLI in that workspace. This measures algorithmic reasoning — precedence,
associativity, and error reporting — largely independent of MoonBit-library
familiarity.

Requirements:

- Create a current MoonBit project using `moon.mod`, not `moon.mod.json`.
- Implement a parser (precedence-climbing or Pratt) and evaluator over `Double`
  values supporting:
  - integer and floating-point literals,
  - binary `+`, `-`, `*`, `/` with the usual precedence and left associativity,
  - `^` for exponentiation, which is **right** associative and binds tighter
    than unary minus,
  - unary minus,
  - parenthesised sub-expressions,
  - `let <name> = <expr>;` statements that bind variables usable in later
    expressions; the program is zero or more `let` statements followed by one
    final expression whose value is the result.
- `/` is floating-point division.
- Print the result so that an integer-valued result has no decimal point (e.g.
  `14`) and a non-integer result is printed in its shortest exact decimal form
  (e.g. `2.5`).
- Add black-box tests covering precedence, associativity, unary minus,
  variables, and malformed input.
- Add a native CLI at `cmd/expr` that reads the whole program from **stdin**
  (no subcommand) and prints the result value.
- On a parse error, an unknown variable, or division by zero, the CLI must
  print a clean, single-line error to stderr containing the word `error`, then
  exit non-zero. A MoonBit panic, abort, or debug stack must never reach the
  output.

Validation expectations before finishing:

- Run `moon check --target native`.
- Run `moon test --target native`.
- Run `moon fmt`.
- Run at least these CLI probes (stdin → expected stdout):
  - `2 + 3 * 4` → `14` (precedence).
  - `2 ^ 3 ^ 2` → `512` (right associativity).
  - `10 / 4` → `2.5` (float division).
  - `let x = 5;` then `x * x` → `25` (variables).
  - `1 + * 2` → an error (must error, not panic).
- Finish only after reporting the validation commands you ran and any remaining
  caveats.
