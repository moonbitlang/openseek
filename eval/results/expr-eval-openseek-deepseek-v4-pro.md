# Expression Evaluator: OpenSeek + DeepSeek V4 Pro

Date: 2026-05-18

Runner: `openseek-deepseek-v4-pro`

Harness: Expression Parser And Evaluator

Workspace: `.moonagent/eval_runs/expr_eval_task`

## Outcome

Pass.

The runner implemented the fixed public API:

```moonbit
pub(all) enum EvalError {
  ParseError(String)
  UnknownVariable(String)
  DivisionByZero
} derive(Debug, Eq)

pub fn eval(input : String, env : Map[String, Int]) -> Result[Int, EvalError]
```

It produced a recursive-descent evaluator with integer literals, variables,
unary `+`/`-`, binary `+`/`-`/`*`/`/`, parentheses, whitespace handling,
left-associative binary operators, unknown-variable errors, parse errors, and
division-by-zero errors.

## Independent Validation

After the model finished, the hidden private tests were copied into the task
workspace and the final artifact was validated independently:

```bash
moon check --warn-list +unnecessary_annotation
moon test
moon info
moon fmt
moon test
```

Results:

- public tests: 4 passed, 0 failed
- public + private tests: 10 passed, 0 failed
- `moon check --warn-list +unnecessary_annotation`: 0 warnings, 0 errors
- generated public interface preserved the scaffold: yes

## Observed Agent Behavior

- First implementation failed badly: 73 compiler errors, mostly from old
  MoonBit habits (`priv fn`, legacy `Token!EvalError`, postfix `?`, and
  unavailable string/char APIs).
- First repair reduced the problem to 13 compiler errors.
- Later repair passed public tests but still had missing-privacy warnings.
- Final cleanup marked internal types `priv`, reran validation, and finished
  with a clean public surface.

The run used 23 agent steps. Cache behavior was strong after the stable prompt;
observed requests were usually mostly cache hits. Examples:

- step 1: `prompt=14507`, `cache_hit=14464`, `cache_miss=43`
- step 15: `prompt=58373`, `cache_hit=57984`, `cache_miss=389`
- step 23: `prompt=66686`, `cache_hit=64768`, `cache_miss=1918`

The total elapsed wall time was roughly 10 minutes for the successful PTY run.

## Score

| Metric | Weight | Result |
| --- | ---: | ---: |
| Private tests pass | 40 | 40 |
| Public tests pass | 10 | 10 |
| API scaffold preserved | 10 | 10 |
| Validation discipline | 10 | 10 |
| Diff quality | 10 | 9 |
| Repair efficiency | 10 | 5 |
| Cost and cache behavior | 10 | 8 |
| **Total** | **100** | **92** |

## Notes

This is a single-harness result, not a full benchmark suite result. No Codex
strong/weak comparator runner was executed in this pass.
