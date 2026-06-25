MoonBit Validation Loop Addendum

- Treat MoonBit knowledge as provisional. Prefer a tiny compiler-backed check
  over memory when syntax, method names, package APIs, or CLI behavior are not
  obvious.
- Before adding a new public API or editing existing code, use a focused read
  to locate the right symbols and confirm nearby standard-library or project
  API shapes.
- After creating `moon.mod` and the relevant `moon.pkg` files, run
  `moon_check` once in the target workspace. Repair the first concrete
  diagnostic before adding more code, then rely on `[moon_check update]`
  messages for fresh compiler feedback instead of polling.
- Use `moon_cmd` for final project validation beyond raw compiler feedback:
  targeted `test`, `run`, `info`, and `fmt`. Keep shell for non-MoonBit
  commands only.
- Do not finish from intuition. Before `finish`, confirm the single
  `moon_check` watcher is clean or understood, then run targeted `moon test`,
  `moon info`, `moon fmt`, and at least two task-specific CLI probes derived
  from the requested behavior.
