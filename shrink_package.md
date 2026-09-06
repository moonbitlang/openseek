# Shrinking a package's public interface (MoonBit)

A semantics-preserving sweep that makes each package export only what other
packages actually use. Repo-agnostic; drive it with `moon ide analyze`.

## Method

1. **Measure, don't guess.** `moon ide analyze <pkg>` prints every exported
   symbol (values, methods, struct fields, enum variants) with
   `usage: N (M in test)`. Real usage = `N − M`. It also flags `pub(all)` /
   `pub(open)` that can narrow to `pub`. Script the sweep: run it over every
   package first and rank packages by zero-real-usage count — fix the worst
   first. Two count semantics to internalize:
   - **Counts are cross-package only.** Same-package references never count,
     so a symbol used ten times in its own package still shows `usage: 0`.
     Those are the easiest wins: drop `pub` and nothing else moves (the
     definition stays used, so no unused-symbol warning fires).
   - **Blessed exports still list — filter on the annotation.** A symbol
     kept in `exports.mbt` is NOT dropped from the output; it appears with
     `, in exports.mbt` appended to its usage comment. A sweep script that
     strips or ignores everything after `//` (this round's did) re-surfaces
     every deliberately kept export as a zero-usage candidate and drowns the
     ranking in already-classified keeps. Parse the annotation and subtract
     those rows first.
2. **Classify each zero-real symbol** — the deny-warn gate forces exactly
   three outcomes:
   - **Test-only usage (`N > 0, N == M`)** → first check HOW consumers import
     the package: `import { ... } for "test"` in their `moon.pkg` means the
     package is a test kit by design — exempt it wholesale (e.g. a
     `testkit/`). Otherwise decide seam vs incident: a symbol many packages'
     tests lean on (a store seeder, a fixture constructor, a policy probe) is
     a deliberate test seam → `exports.mbt`, documented. A getter poked by
     one adjacent test is incidental → remove `pub` and move that test into
     the package (whitebox/inline). Test usage is never API justification by
     itself.
   - **No usage at all (`N == 0`), plausibly intentional** (documented
     tunables, one of a symmetric family, protocol surface) → keep `pub` but
     move the block to `exports.mbt` in that package. The file IS the
     convention: everything in it is exported on purpose despite no internal
     consumer.
   - **No usage at all, vestigial** → delete the block. (Making it `priv`
     instead just trades an over-export for an unused-symbol warning.)
3. **Verify per package, not per sweep**: `moon check --deny-warn`, run the
   package's tests, then `moon info` and check the `.mbti` diff shrank the way
   you intended. The `.mbti` diff is the review artifact.

## Traps

- **Cross-workspace consumers are invisible.** `moon ide analyze` only sees
  the current workspace. A package consumed by a sibling module (another
  `moon.work`, a JS app module, a desktop shell) shows zero usage here while
  being load-bearing there. Union usage from every workspace that imports it
  before shrinking — and put the symbols such a consumer needs in
  `exports.mbt` with a comment naming that consumer. (The analyzer keeps
  listing them, annotated `, in exports.mbt` — see step 1; filter on that
  marker in the sweep script.)
- **Target-only consumers are invisible too — including to the narrowability
  flags.** A JS-only package errors out of `moon ide analyze` ("no package
  directories found in input paths") AND its usages of everything else are
  missing from the counts and from the `(all) or (open) can be removed`
  hints. Real case: `ParsedLog` was flagged narrowable while the js-only viz
  app constructs it with a struct literal — narrowing compiles clean under
  native `moon check --deny-warn` (which never builds the js app) and breaks
  the bundle build. Grep js/web consumers for every candidate, and verify
  with `moon check --target js` (or the app's bundle build) after any
  narrowing a js package might construct.
- **Published modules**: if the module is on a registry, everything `pub` is
  potentially someone's dependency. Get the owner's explicit OK that
  in-repo usage is the yardstick (here: yes).
- **Blackbox tests break at compile time** when their symbol goes priv —
  that's the signal, not a problem. Convert those tests rather than keeping
  the export.
- **Struct fields**: don't bother marking fields `priv` on a plain `pub`
  struct — the 2026 toolchain flags the modifier as redundant there
  (deny-warn fails). Field-level shrink only matters for `pub(all)` structs,
  where external construction needs every labeled field; check construction
  sites before narrowing those.
- **Shrinking surfaces dead code beyond visibility.** Once a constructor goes
  package-private, `unused_default_value` and friends start firing — e.g. a
  parameter default that no caller ever exercised (an upstream wrapper owned
  the real default). Treat these warnings as findings: delete the dead
  default (make the parameter required), don't suppress the warning.
- **Analyzer notes are hints, not proofs.** `(all) or (open) can be removed`
  and usage counts can miss reflection-ish uses (derive output consumed as
  JSON keys, wire contracts). Compile + full tests after each package.
- **Dead packages**: a package whose every export is unused may itself be
  unimported — check `moon.pkg` importers; deleting the package beats
  shrinking it.
- **`pub impl` (trait impls, incl. derive-adjacent Show/ToJson/FromJson)**
  with zero external usage usually demote to plain `impl` — in-package and
  derive-chain uses don't need `pub`. Two exceptions: (a) round-trip impls on
  durable-record types are protocol surface — keep them (exports.mbt);
  (b) a trait impl whose trait OBJECT crosses the package boundary cannot
  demote — the consumer package invoking through `&Trait` needs the
  conformance public ("implementation of method X is private" is the
  compiler telling you this). Derive-generated impls surface through the
  explicit `pub extend T with Trait::{m}` promotion lines the 2026 toolchain
  requires (E0079); those lines are the shrinkable block. A promotion nobody
  calls as `T::m` / `x.m()` cross-package becomes
  `#doc(hidden)` + `#deprecated` + `pub extend ...` — the trait impl stays
  usable through the trait, the promoted method drops out of the `.mbti`, and
  any cross-package dot-call that still needs it fails deny-warn (E0020), so
  the compiler tells you exactly which promotions to leave un-deprecated.
  A plain non-`pub` `extend` does not work: E0079 keeps firing because the
  derived `impl` itself is public, and the private promotion is then unused.
- **Enum variants and `pub(all)` struct fields** are not individually
  shrinkable — act on the analyzer's narrowability flag for the whole type,
  and skip per-variant/per-field rows unless the type is plain `pub`.

- **Make edit tooling fail on no-change.** A regex that silently matches
  nothing turns a whole category of edits into no-ops that still report
  success (this sweep's `pub(all)` narrowing was a no-op for three batches
  before the residual-stats check caught it). Count *changed* files/lines,
  not matched declarations — and re-run the analyzer at the end as an
  independent audit of what actually changed.

## Order of work

Pilot one leaf package end-to-end (smallest blast radius, validates the
test-conversion mechanics), then sweep families bottom-up (leaf packages
before the packages that import them), committing per family so review and
bisection stay tractable.
