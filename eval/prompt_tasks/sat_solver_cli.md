You are running a MoonBit coding-agent benchmark.

Workspace: {{WORKSPACE}}

Build a small MoonBit DIMACS CNF parser and DPLL SAT solver library and native
CLI in that workspace. This measures algorithmic depth with objective answers,
and is deliberately light on MoonBit-specific APIs.

Requirements:

- Create a current MoonBit project using `moon.mod`, not `moon.mod.json`.
- Parse DIMACS CNF: `c ...` comment lines, a `p cnf <vars> <clauses>` header,
  and clauses given as space-separated non-zero signed integers terminated by
  `0`. A clause consisting only of `0` is the empty clause.
- Implement a DPLL solver with unit propagation and pure-literal elimination.
- Add black-box tests covering satisfiable and unsatisfiable formulas,
  comments, the empty clause, and a larger propagation chain. For a satisfiable
  formula, a test should verify the reported assignment actually satisfies every
  clause.
- Add a native CLI at `cmd/sat` that reads a DIMACS CNF from **stdin** and
  prints the verdict:
  - If satisfiable, print `SATISFIABLE` on the first line and, on the second
    line, `v ` followed by a space-separated satisfying assignment as signed
    literals (positive for true, negative for false) terminated by ` 0`.
  - If unsatisfiable, print exactly `UNSATISFIABLE`.
- An empty clause makes the whole formula unsatisfiable.
- On malformed DIMACS input the CLI must print a clean, single-line error to
  stderr containing the word `error`, then exit non-zero. A MoonBit panic,
  abort, or debug stack must never reach the output.

Validation expectations before finishing:

- Run `moon check --target native`.
- Run `moon test --target native`.
- Run `moon fmt`.
- Run at least these CLI probes:
  - a satisfiable formula (must print a `v ` assignment line).
  - a contradiction such as `(x1) ∧ (¬x1)` → `UNSATISFIABLE`.
  - a formula containing `c` comment lines.
  - a formula containing the empty clause → `UNSATISFIABLE`.
- Finish only after reporting the validation commands you ran and any remaining
  caveats.
