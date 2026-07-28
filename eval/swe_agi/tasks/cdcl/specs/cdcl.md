# CDCL SAT Solver + DIMACS CNF — specification for this repo

This document is a **practical, test-oriented spec** for the `cdcl`
package. It summarizes:

- The DIMACS CNF input format the suite uses, and
- The required behavior of the SAT solver API (CDCL-style) as validated by the
  test corpus.

It is **not** a full SAT-solver textbook, and it is not a verbatim copy of any
external standard.

## Objectives (what the implementation must do)

The `cdcl` package expects an implementation that can:

1. Parse a DIMACS CNF file into an internal CNF representation (`CnfFormula`).
2. Solve the CNF using a correct SAT algorithm (CDCL recommended).
3. Return either:
   - `SolveResult::Sat(model~ : Model)` with a satisfying assignment, or
   - `SolveResult::Unsat` when the formula is unsatisfiable.
4. Ensure that any returned `Model` satisfies `cnf.eval(model) == true`.

The test suite primarily uses satisfiable benchmark instances and checks that
the solver returns a model that makes the CNF evaluate to true.

## Primary references

- DIMACS CNF format (vendored): `cdcl/specs/DIMACS.md`

For CDCL background (non-normative reading):

- “Conflict-Driven Clause Learning” (CDCL) overviews in SAT literature.

## API contract (from `cdcl/cdcl_spec.mbt`)

- `DimacsParser::parse(source : Bytes) -> CnfFormula raise`
- `solve(cnf : CnfFormula) -> SolveResult`
- `CnfFormula::eval(self : CnfFormula, model : Model) -> Bool`

Types:

- `Model`: represents a truth assignment for variables.
- `CnfFormula`: conjunctive normal form formula (AND of OR-clauses).

The exact internal structure of `Model`/`CnfFormula` is up to the implementation,
as long as it satisfies the behavioral contract.

## DIMACS CNF parsing rules (suite-relevant)

See `cdcl/specs/DIMACS.md` for full details. Key requirements:

- Ignore comment lines starting with `c` (commonly when `c` is the first
  non-whitespace character on a line).
- Header line: `p cnf <num_vars> <num_clauses>`
- Clauses are sequences of non-zero integers (literals) terminated by `0`.
- Whitespace is flexible; clause boundaries are determined only by `0`, so a
  clause may span multiple lines.

Recommended strictness (compatible with most benchmarks and aligns with the
vendored spec):

- Enforce that exactly `<num_clauses>` clauses are present.
- Enforce that each literal `k` satisfies `1 <= abs(k) <= <num_vars>`.
- Reject malformed tokens or premature EOF mid-clause.

## SAT semantics (CnfFormula::eval contract)

- Variables are indexed `1..N`.
- A literal `k` is true under a model if:
  - `k > 0` and variable `k` is assigned true, or
  - `k < 0` and variable `abs(k)` is assigned false.
- A clause is satisfied if any of its literals is true.
- A CNF is satisfied if all clauses are satisfied.

`CnfFormula::eval(model)` must implement this semantics.

## Solver correctness expectations

The tests call `check_sat(path)` (see `cdcl/check.mbt`), which asserts:

1. `solve(cnf)` returns `Sat(model~)`.
2. `cnf.eval(model)` is true.

Therefore, a solver must:

- Produce a complete-enough model for all variables referenced by the CNF.
- Not return `Sat` with an incorrect model.

If you also implement UNSAT detection, `check_unsat` is provided and may be used
by future tests.

## CDCL algorithm notes (non-normative, but practical)

Any correct SAT algorithm is acceptable, but CDCL is recommended due to test
instance sizes. A typical CDCL implementation includes:

- Unit propagation (watched literals)
- Decision heuristic (VSIDS or similar)
- Conflict analysis with 1-UIP clause learning
- Non-chronological backtracking
- Restarts (optional)

The suite does not mandate a particular heuristic; it mandates correctness and
reasonable performance on the included benchmark set.

## Conformance checklist (high value test coverage)

- Robust DIMACS parsing (comments, whitespace, multi-line clauses)
- Solving benchmark CNFs under `cdcl/dimacs/*`
- Producing a satisfying `Model` for SAT cases
- `CnfFormula::eval` correctness (the suite uses it to validate the model)

## DIMACS parsing edge cases worth specifying explicitly

Although the suite primarily feeds standard benchmark CNFs, a robust parser
should define behavior for:

- Comments:
  - Lines whose first non-whitespace char is `c` are comments and ignored.
  - Comments may appear before or after the header.
- Clause spanning:
  - A clause may span multiple lines; only the terminating `0` ends a clause.
- Empty clause:
  - A clause consisting solely of `0` is the empty clause and makes the CNF
    unsatisfiable. If you implement `Unsat`, this is an easy early-exit.
- Duplicate literals:
  - Allowed; do not change semantics.
- Tautological clauses:
  - A clause containing both `k` and `-k` is always true; can be dropped.

The vendored `cdcl/specs/DIMACS.md` is a good implementation reference and
describes a strict policy (exactly M clauses, no out-of-range literals).

## Model representation requirements

The tests only observe `Model` through `CnfFormula::eval(model)`. Therefore the
implementation must ensure:

- `Model` can represent assigned truth values for all variables referenced.
- `eval` is total: it must return a Bool for every literal without panicking.
- If the solver uses three-valued assignment internally (true/false/unassigned),
  it must finalize unassigned variables before returning `Sat(model~)` or make
  `eval` treat unassigned in a way that preserves correctness (the simplest is
  to finalize).

## Solver behavior expectations beyond correctness

The included benchmarks are non-trivial. To avoid timeouts, implementations
should incorporate at least:

- Efficient unit propagation (watched literals strongly recommended).
- Some branching heuristic (even a simple one).
- Clause learning and non-chronological backtracking if using CDCL.

The tests don’t assert “learned clause counts”, but they implicitly require the
solver to finish within reasonable time on the benchmark set.
