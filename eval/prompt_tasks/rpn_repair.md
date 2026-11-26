You are running a MoonBit coding-agent benchmark.

Workspace: {{WORKSPACE}}

Repair a small, buggy MoonBit reverse-Polish (RPN) calculator and wrap it in a
native CLI. This measures debugging discipline: finding and fixing specific
defects while keeping a fixed public API, rather than rewriting from scratch.

Start from this exact implementation. It compiles, but it is wrong. Recreate it
verbatim in your library, then fix only what is needed to satisfy the contract
below. Keep the public signature `pub fn eval(input : String) -> Double raise`
unchanged.

```moonbit
///| Evaluate a whitespace-separated reverse-Polish expression.
pub fn eval(input : String) -> Double raise {
  let stack : Array[Double] = []
  for token in input.split(" ") {
    let tok = token.to_owned()
    if tok == "" {
      continue
    }
    match tok {
      "+" => {
        let a = stack.pop().unwrap()
        let b = stack.pop().unwrap()
        stack.push(a + b)
      }
      "-" => {
        let a = stack.pop().unwrap()
        let b = stack.pop().unwrap()
        stack.push(a - b)
      }
      "*" => {
        let a = stack.pop().unwrap()
        let b = stack.pop().unwrap()
        stack.push(a * b)
      }
      "/" => {
        let a = stack.pop().unwrap()
        let b = stack.pop().unwrap()
        stack.push(a / b)
      }
      _ => stack.push(@string.parse_double(tok))
    }
  }
  stack.pop().unwrap()
}
```

Include these two black-box tests unchanged; they currently fail and must pass
after your repair:

```moonbit
test "subtraction order" {
  assert_eq(eval("5 3 -"), 2.0)
}

test "division order" {
  assert_eq(eval("6 2 /"), 3.0)
}
```

Contract the repaired code must satisfy:

- Correct RPN operand order: `x y -` computes `x - y` and `x y /` computes
  `x / y` (the two provided tests encode this).
- Division by zero, a stack underflow (an operator with too few operands), an
  expression that leaves more than one value on the stack, and an unrecognised
  token must each be reported as a clean, single-line error to stderr containing
  the word `error`, followed by a non-zero exit. A MoonBit panic, abort, or
  debug stack must never reach the output.
- Requirements:
  - Create a current MoonBit project using `moon.mod`, not `moon.mod.json`.
  - Add a native CLI at `cmd/rpn` that reads the whole RPN expression from
    **stdin** and prints the numeric result. Print an integer-valued result with
    no decimal point (e.g. `4`).
  - Do not change the two provided tests or the `eval` signature. Prefer a
    minimal, targeted diff over a rewrite.

Validation expectations before finishing:

- Run `moon check --target native`.
- Run `moon test --target native`.
- Run `moon fmt`.
- Run at least these CLI probes:
  - `8 2 /` → `4`.
  - `1 0 /` (division by zero → error, not `inf` or a panic).
  - `1 +` (underflow → error, not a panic).
  - `1 2` (leftover operands → error).
  - `1 x +` (unknown token → error, not a panic).
- Finish only after reporting the validation commands you ran and any remaining
  caveats.
