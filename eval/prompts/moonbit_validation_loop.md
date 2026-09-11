MoonBit Validation Loop Addendum

- Treat MoonBit knowledge as provisional. Prefer a tiny compiler-backed check
  over memory when syntax, method names, package APIs, or CLI behavior are not
  obvious.
- Before adding a new public API or editing existing code, use a focused
  `@builtin/read.mbtx` read to locate the right symbols and confirm nearby
  standard-library or project API shapes.
- After creating `moon.mod` and the relevant `moon.pkg` files, run
  `moon check` from an `mbtx` snippet once in the target workspace. Repair
  the first concrete diagnostic before adding more code, and re-run it when
  you need fresh compiler feedback.
- Use `mbtx` snippets for final project validation beyond raw compiler
  feedback: targeted `moon test`, `moon run`, `moon info`, and `moon fmt`.
- Do not finish from intuition. Before `finish`, confirm the latest
  `moon check` output is clean or understood, then run targeted `moon test`,
  `moon info`, `moon fmt`, and at least two task-specific CLI probes derived
  from the requested behavior.
