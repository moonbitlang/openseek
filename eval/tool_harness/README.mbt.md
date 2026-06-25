# Tool Harness

`bobzhang/openseek/eval/tool_harness` is a deterministic harness for the local
tool layer. It creates temporary fixtures, dispatches every built-in tool
through `agent_tool.execute_tool_call`, and returns a shared `eval/report`
report.

This complements the model-facing file-edit eval. The file-edit harness answers
whether an AI can choose tools well; this package answers whether each tool can
be invoked correctly through the same typed boundary the agent loop uses.

## Coverage

- `read`: ranged text read from a virtual filesystem fixture.
- `write`: creates a file and compares disk state with `testkit/filesystem`.
- `edit`: exact replacement plus final disk-state comparison.
- `shell`: harmless process execution with exit-code output.
- `moon_check`: real
  `moon check --watch --diagnostic-limit 10` on a temporary
  MoonBit package.
- `moon_cmd`: real `moon test` on the same style of temporary package.
- `finish`: verifies the control action returned by the loop terminator.

## Example

```moonbit check
///|
async test "run deterministic tool harness" {
  let report = @tool_harness.run_harness()
  assert_true(report.all_passed())
  assert_true(report.markdown().contains("# Tool Harness"))
}
```

Run it directly with:

```bash
moon test eval/tool_harness
```
