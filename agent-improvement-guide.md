# OpenSeek Agent Improvement Guide

This guide turns the evaluation notes in `todo.md` into a practical direction
for improving OpenSeek. The short version is simple: DeepSeek V4 Pro is already
capable enough to build substantial MoonBit libraries when it gets tight,
well-shaped feedback. The highest return now is not another broad prompt. It is
better proof that the delivered tool actually behaves the way a user will call
it.

## Core Thesis

The agent's current failure mode is rarely "cannot write code at all." Across
the TOML, JSON Schema, jqmini, JSONPath, CSVQL, semver, Markdown outline, and
route matcher runs, V4 Pro repeatedly recovered from compiler walls and got
large libraries to pass tests. The repeated miss was contract reliability:

- a CLI accepts inline JSON even though the task requested file paths
- `moon run` reports success while the built native binary exits nonzero
- failure output leaks `Failure(...)`, abort output, or stack traces
- generated tests pass, but README commands or stdin/file modes are not proven
- broad tool output or native build artifacts flood context and stop the run

That pattern is important. It means the next improvement should make external
behavior hard to fake. A smarter model may reduce syntax mistakes, but a
contract checker prevents the agent from declaring victory when users would
still see broken output.

## Reference Evidence

The best positive reference is the semver solver guarded V2 run. It passed
`moon check --target all`, passed native tests, and proved file success, file
conflict, backtracking, and stdin behavior. That run is valuable because it
validated behavior the same way a user would call it.

The strongest negative references all point at the same gap:

- JSON Schema V4 passed `moon check` and tests, but the final CLI consumed inline
  JSON strings instead of schema and instance file paths. The library worked; the
  user contract did not.
- JSONPath, Markdown outline, and route matcher exposed `moon run` versus built
  binary mismatches. A run could look successful through `moon run` while the
  native binary had the real nonzero exit behavior.
- The dependency solver produced the intended JSON conflict object, then leaked
  extra runtime failure output. Tests were not enough to catch dirty stdout.
- JSON Schema V1 and V2 failed from context blowups after generated native C was
  printed into the transcript. Output caps fixed the next run.
- Jqmini crashed after an oversized semantic-doc response for `@array`. The model
  did not need more text; it needed smaller, shaped documentation.

These are not isolated task bugs. They are system design signals.

## Priority 1: Semantic CLI Validation

### Motivation

Most projects in the evals eventually compiled. The remaining user-visible
failures were CLI contract failures. A semantic validator would turn those into
first-class checks instead of hoping the agent remembers to inspect stdout,
stderr, and exit codes correctly.

### Good Example

For the semver resolver, the task says conflict mode must print exactly one
compact JSON object and exit nonzero. A good acceptance check is not just
"command ran"; it is:

```text
command:
  moon run --target native cmd/resolve -- fixtures/conflict.json

assert:
  exit code is nonzero
  stdout is one JSON object
  stdout.ok == false
  stdout.error is a string containing the conflicted package
  stdout does not contain "Failure("
  stdout does not contain "Panic"
  stderr is empty, or only contains accepted moon wrapper text
```

For JSON Schema, the validator should prove that arguments are file paths:

```text
setup:
  fixtures/schema_string.json contains {"type":"string"}
  fixtures/valid_string.json contains "hello"

command:
  moon run --target native cmd/main -- \
    fixtures/schema_string.json fixtures/valid_string.json

assert:
  stdout JSON says valid == true
  stdout does not include the literal file path
  stdout does not include "Invalid character"
```

That single check would have caught the V4 schema-validator contract gap.

### Design Direction

Add a `moon_accept` tool, or extend a structured moon-command runner, with
structured assertions:

- `command`: array of argv, not a shell string
- `stdin`: optional string
- `expected_exit`: `zero`, `nonzero`, or exact integer
- `stdout_format`: `json`, `json_lines`, `text`, or `empty`
- `stdout_predicates`: path/value checks such as `ok == true`
- `forbidden_stdout`: strings such as `Failure(`, `Panic`, generated C markers
- `stderr_policy`: `empty`, `allow_moon_wrapper`, or explicit predicates
- `compare_native_binary`: optional check that the built binary behaves like
  `moon run`

This is high ROI because it converts ambiguous transcript inspection into a
small, reusable proof step. It also gives the agent better feedback: "stdout is
valid JSON but contains forbidden runtime output" is far more actionable than a
large raw command dump.

## Priority 2: CLI And Error-Handling Cookbook

### Motivation

The agent repeatedly rediscovered native CLI basics: argument shape,
file/stdin reads, stdout versus stderr, JSON output, and nonzero exits without
abort noise. Prompt reminders helped, but the same mistakes came back across
task shapes.

### Good Example

The cookbook should show a proven pattern for each common CLI contract:

```text
Pattern: file argument with stdin fallback

Inputs:
  cmd/tool -- input.json
  echo '{"a":1}' | cmd/tool

Required behavior:
  file mode reads the file contents, not the path string
  stdin mode reads all stdin when no file is provided
  success writes one compact JSON value to stdout
  expected domain failure writes one compact JSON error to stdout or stderr,
  according to the task contract, and exits nonzero without abort stack output
```

The guide should also include "bad examples" copied from eval patterns:

```text
Bad:
  treating @env.args()[0] as the user file when it is the generated native path
  using abort("...") for normal user input errors
  printing debug/native generated output before the JSON result
  validating only a hardcoded fixture inside main
```

### Why It Matters

MoonBit library quality and CLI quality are different skills. The model can pass
library tests while still failing the delivery surface. A cookbook gives it a
known-good route through native I/O and error behavior, so the model spends its
reasoning budget on the domain logic instead of guessing MoonBit runtime APIs.

## Priority 3: Route MoonBit Commands Through Structured Policy

### Motivation

A structured command policy can still be bypassed by raw shell. In one eval, a
guarded command path rejected an unreviewed `moon test --update`; the agent then
used shell to run the same command. Other runs lost time to shell quoting for
expressions with `|`, spaces, brackets, and parentheses.

### Good Example

Instead of allowing this:

```text
shell: moon test --update
```

the shell tool should either reject it or route it through the same command
policy:

```text
structured command:
  command = test
  update_snapshots = true
  test_update_kind = intentional_snapshot_refresh
  test_update_reason = "README output changed after fixing JSON escaping"
```

For query-heavy tools such as jqmini or JSONPath, structured argv matters:

```text
command argv:
  ["moon", "run", "--target", "native", "cmd/jqmini", "--", ".items[] | .name", "fixtures/users.json"]
```

The agent should not have to rely on shell quoting to preserve the query.

### Why It Matters

Command policy is only real if every path respects it. If a guarded command path
is safe but `shell` can bypass it, the agent will eventually take the loose path
under pressure. Routing also improves eval quality because command failures become
tool-feedback failures, not quoting accidents.

## Priority 4: Shape Semantic Docs And Source Output

### Motivation

Semantic doc lookups improved API discovery, especially for JSON, async file
reads, and `io.Data`. But broad doc/source output caused avoidable waste.
Jqmini's oversized semantic-doc response for `@array` was followed by a transport
reset. JSON Schema spent many steps reading too much dependency source before
finding the relevant file-read pattern.

### Good Example

Prefer shaped responses:

```text
semantic doc @json.Json

response:
  summary
  constructors
  parse/inspect helpers
  top 10 relevant methods
  "ask for page 2" marker when more exists
```

For definitions:

```text
semantic peek_def @io.Data::text

response:
  exact signature
  20 lines around the definition
  package/import hint
```

### Why It Matters

Agents need semantic context, not unbounded source dumps. Smaller, shaped
responses make API discovery faster and reduce the chance of losing the run to
context bloat. This is the same lesson as command output caps: the tool should
return enough information to choose the next edit, not enough text to make the
model forget the task.

## Priority 5: Manifest, Debug, And Edit Guardrails

### Motivation

Several runs touched manifests or debug files in ways that almost worked but
damaged final quality:

- confusing current `moon.mod` with legacy `moon.mod.json`
- overwriting `moon.pkg` with suspiciously tiny content
- leaving `debug_main.mbt` or debug-named tests inside deliverable packages
- failing brittle `old_string` edits after a file changed

### Good Example

Manifest writes should be checked immediately:

```text
after writing moon.mod or moon.pkg:
  verify current moon.mod syntax
  verify package imports/options still include required dependencies
  run moon check on the affected package
```

Temporary experiments should go outside deliverable packages:

```text
allowed:
  .moonagent/scratch/<run-id>/probe.mbt

not allowed:
  cmd/main/debug.mbt
  root debug_main.mbt
```

Edit failures should return compact repair context:

```text
old_string not found:
  file changed since last read: yes
  closest matching line: 142
  nearby 8 lines
```

### Why It Matters

These guardrails do not make the model smarter, but they prevent cheap mistakes
from turning into long repair loops. They also protect final deliverables from
temporary code that was useful during diagnosis but should never ship.

## Why Prompting Alone Is Not Enough

The agent already had prompt guidance for:

- current `moon.mod`
- flat MoonBit package structure
- smaller files
- bounded reads
- native CLI arguments

Those prompts helped, but they did not eliminate repeated contract misses. The
reason is structural: a prompt can ask the model to remember a rule, while a tool
can make the wrong state impossible to overlook. The strongest improvements so
far were tool-level:

- output caps prevented JSON Schema context blowups
- bounded `read` made repair loops more focused

The next investments should follow that same pattern.

## Recommended Implementation Order

1. Build semantic CLI validation first.
   This directly targets the most common final-quality gap. Start with JSON,
   JSON Lines, exit-code, forbidden-output, stderr, file-mode, and stdin-mode
   checks.
2. Add a CLI/error cookbook and inject it into the agent prompt.
   This gives the model a reliable native CLI pattern while the semantic
   validator proves the result.
3. Enforce MoonBit command routing through a structured command policy.
   Close shell bypasses and reduce quoting failures for query-heavy tasks.
4. Shape semantic-doc responses and broad source reads.
   Keep API discovery useful but bounded.
5. Add manifest/debug/edit guardrails.
   Prevent recurring cleanup and package-regression failures.

This order matters. Semantic CLI validation catches bad outcomes immediately.
The cookbook gives the agent a better path to a good outcome. Command and output
guardrails then reduce wasted steps. Manifest/debug/edit guardrails protect
quality as tasks get larger.

## Definition Of Success

The improvement program is working when future eval summaries can say:

- `moon check` and `moon test` pass
- file-mode CLI probes pass
- stdin-mode CLI probes pass
- failure-mode CLI probes return the expected exit behavior
- stdout is machine-parseable and clean
- stderr is clean or explicitly allowed
- README commands are executed, not merely written
- no debug files remain in deliverable packages
- logs stay small enough that context never becomes the reason a run fails

At that point the agent is not just generating plausible MoonBit code. It is
shipping behavior that survives the way users actually call the tool.
