# Plan: Examples-over-guidelines prompt experiment

## Hypothesis

Worked, compiler-verified examples teach a model more per token than
imperative guidelines. Predicted mechanism: the dominant failure classes in
the 2026-06-12 prompt-matrix sessions are cross-language habit errors that
rules don't suppress but demonstrations pattern-match away.

## Evidence base (20 archived sessions, workspace-local compiler errors)

| class | count | example | habit |
| --- | --- | --- | --- |
| [0020] deprecated forms | 530 | `view.to_string()`, `not x`, `Map::new()` | stale API memory |
| [3002] struct literal | 318 | `Parser { input, pos: 0 }` | Rust type-prefixed literal |
| [4014] unbound method | 211 | `@strconv::from_str`, `Array::from_iter` | Rust `::` paths, invented APIs |
| [4015]/[0013] type errors | 343 | `from_str[Int](s)`, `c.is_alphanum()` | turbofish, invented methods |
| [4021] unbound ident | 155 | mangled escapes in TOML test fixtures | string-escaping confusion |
| [0029] bad import | 151 | `"local/tomlkit"` in moon.pkg | import path format |

## Intervention

Build 4 compact demos (~15-25 lines each), each spanning several error
classes, and REPLACE the guideline-styled "syntax discipline" portions of
flash_prompt with them, holding total prompt size token-neutral or smaller
(the matrix showed prompt size is load-bearing for flash — bigger is not
allowed to confound the comparison).

1. **Parser-skeleton demo**: struct + `{ field, }` literal (no type prefix),
   `Self` methods, match over string views. Targets [3002], [4015].
2. **Strings demo**: view slicing with `.to_owned()`, char-range patterns
   (`c is ('a'..='z')`), interpolation `\{...}` (not format_with), `#|`
   multiline literal holding a TOML fixture. Targets [0020], [4021].
3. **Numbers/errors demo**: the LIVE (non-deprecated) parse APIs as verified
   today, suberror + raise + catch shape. Targets [4014], [0013], [0020].
4. **CLI+pkg demo**: minimal native main (args + stdin), correct moon.pkg
   with is-main and a correctly formatted import. Targets [0029] and the
   CLI-probe failures.

Verification discipline: every demo must compile/run via `moon run -e`
(or a scratch project for the moon.pkg demo) BEFORE entering the prompt;
demos embedded as ```mbt check blocks where possible so CI re-verifies them
forever (flash_prompt.mbt.md is a blackbox test file).

## Experiment

- Arms (TOML task, 5 trials, concurrency 3, same engine + protocol as the
  matrix, prompts via --system-prompt-file):
  - A: flash x flash_prompt (today's matrix arm, 2/5 — reused as baseline,
    same day/engine/task)
  - B: flash x demos-variant
  - C (only if B is ambiguous on pass rate): demos + retained guidelines
- Primary metric: per-class workspace-local error counts ([3002], [0020],
  [4014], [4021], [0029]) — sharp and low-variance; the hypothesis predicts
  targeted classes drop materially.
- Secondary: pass rate, finish rate, turns, wall clock.
- If B wins on error classes without regressing pass rate: confirmation arm
  pro x demos-variant (5 trials), since the matrix says pro may unify onto
  the condensed prompt.

## Deliverables

- Verified demos in prompt/flash_prompt.mbt.md (CI-checked blocks).
- Results archived under eval/results/ with sessions + README, ledger entry.
- Commits + push on an experiment branch; codex review; no merge.

## Risks

- n=5 noise on pass rate → that's why error-class counts are primary.
- Demos could displace guidelines that were quietly load-bearing → C-arm
  fallback isolates that.
- Verified-today APIs may still emit deprecation warnings under deny-warn →
  verify demos with warnings treated as errors, not just successful runs.

## Revisions after Codex plan review (adopted)

1. Fresh baseline: arm A reruns fresh, interleaved with B/C — today's matrix
   arm is supplementary context only.
2. C always runs: A = guidelines (status quo), B = guidelines REPLACED by
   demos (token-neutral), C = guidelines + demos (additive; also probes the
   size penalty the matrix found).
3. Normalized primary metrics, pre-registered: targeted-class errors per
   compiler invocation; unique targeted diagnostics per session; untargeted
   errors as regression guardrail. Success = >=40% drop in normalized
   targeted errors, untargeted not up >15%, pass rate not below baseline.
4. n=5/arm is a PILOT; promotion to the shipped prompt requires a
   confirmation run (n=10 on the winning arm vs fresh baseline).
5. Leakage guard: demos avoid TOML and INI-like key=value domains entirely
   (arithmetic tokens, date parsing, log lines); the holdout task is an INI
   parser scored on error classes from sessions (the harness validator is
   TOML-only; noted limitation).
6. Identity controls recorded in the results README: prompt sha256, byte
   size, engine commit, model params, task file hash.
7. The moon.pkg demo is verified in a scratch project, not only as a
   markdown check block.
