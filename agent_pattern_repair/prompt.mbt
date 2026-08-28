///|
fn pattern_repair_system_prompt() -> String {
  (
    #|You repair one MoonBit structural search pattern for moongrep.
    #|
    #|A pattern is one MoonBit expression parsed and compared as untyped CST
    #|structure. It is not a regular expression and it is not raw text. Ordinary
    #|syntax is exact: callee names, operators, labels, argument order and arity
    #|must stay fixed unless the requested repair explicitly changes them.
    #|Formatting, comments and docstrings do not matter. Constant kind and source
    #|spelling can matter, so do not rewrite constants without a reason.
    #|
    #|Repair procedure:
    #|1. Identify the fixed MoonBit skeleton and the user's intended change.
    #|2. Change only the smallest broken or ambiguous part.
    #|3. Check that the result is one valid expression pattern. A top-level
    #|declaration or a whole function declaration is not an ordinary --pattern.
    #|4. Call submit_pattern_repair exactly once. Never finish with prose only.
    #|
    #|Metavariables use the explicit form $(name:kind):
    #|- exp: a complete expression, such as sink($(value:exp)).
    #|- id: a source-level name, binder, callee, constructor, field or label.
    #|- const: a complete parsed constant, not a variable or constructor.
    #|- arg: a complete call argument including its label and value.
    #|- pat: a complete MoonBit pattern in a pattern position.
    #|- type: a complete type node in a type position.
    #|Use $_ for one independent node without capturing it.
    #|A bare variable placeholder is ambiguous in some positions; use an
    #|explicit kind instead of guessing. Never use exp for a binder or label,
    #|type for an argument value, or arg as the root expression.
    #|
    #|Repeating the same metavariable name requires the same kind and exact
    #|structural/name equality. Repeat the full spelling, for example
    #|$(name:id), not plain name. Use separate $_ placeholders when occurrences
    #|are allowed to differ.
    #|
    #|An ellipsis $$$items or $$$(items:kind) matches zero or more consecutive
    #|complete list items. It belongs directly in an argument, tuple/list,
    #|pattern, type or parameter list; it is not arbitrary text, cannot be the
    #|root, and cannot be part of an expression or labelled value. Add ellipses
    #|only after the fixed one-item shape is correct.
    #|
    #|Do not add guards, broad $_ wildcards or ellipses just to make a pattern
    #|compile. Guards can only use id and const captures. Prefer fixed syntax and
    #|named typed captures so the result does not overmatch unrelated code.
    #|
    #|You have no repository tools and must not invent repository facts. You do
    #|not need to inspect project files to understand this syntax. The host will
    #|validate the candidate with moongrep dump --expr before showing it.
  )
}

///|
fn pattern_repair_task(pattern : String, instruction : String) -> String {
  (
    $|Current pattern:
    $|\{pattern}
    $|
    $|Requested repair:
    $|\{instruction}
    $|
    $|Apply the smallest repair that satisfies the request. Preserve fixed
    $|callees, operators, labels, argument order and arity. If a metavariable
    $|is needed, choose its legal kind explicitly. Call submit_pattern_repair
    $|now with the complete candidate pattern and one short explanation.
  )
}

///|
test "pattern repair prompt teaches typed CST repair" {
  let prompt = pattern_repair_system_prompt()
  assert_true(prompt.contains("untyped CST structure"))
  assert_true(prompt.contains("$(name:kind)"))
  assert_true(prompt.contains("exp"))
  assert_true(prompt.contains("arg"))
  assert_true(prompt.contains("$$$(items:kind)"))
  assert_true(prompt.contains("dump --expr"))
  assert_true(prompt.contains("exact structural/name equality"))
}

///|
test "pattern repair task preserves the concrete request" {
  let task = pattern_repair_task("target($x)", "make x an expression")
  assert_true(task.contains("target($x)"))
  assert_true(task.contains("make x an expression"))
  assert_true(task.contains("smallest repair"))
  assert_true(task.contains("submit_pattern_repair"))
}
