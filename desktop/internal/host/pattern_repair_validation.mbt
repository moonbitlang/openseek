///|
/// Keep candidate validation bounded and deterministic. The Agent must never
/// choose the executable or invoke this command directly; the host owns both.
const PatternRepairDumpMaxDiagnosticUnits : Int = 1000

///|
fn pattern_repair_dump_args(pattern : String) -> Array[String] {
  ["dump", "--expr", pattern]
}

///|
fn pattern_repair_diagnostic(stderr : String) -> String {
  let detail = stderr.trim().to_owned()
  guard !detail.is_empty() else {
    return "Pattern validation failed without a diagnostic."
  }
  guard detail.length() > PatternRepairDumpMaxDiagnosticUnits else {
    return detail
  }
  detail[:PatternRepairDumpMaxDiagnosticUnits].to_owned() + "..."
}

///|
fn pattern_repair_validation_code(stderr : String) -> String {
  let lower = stderr.to_lower()
  if lower.contains("not a valid") ||
    lower.contains("lexical error") ||
    lower.contains("parse error") {
    "invalid_pattern"
  } else if lower.contains("permission denied") ||
    lower.contains("access is denied") {
    "permission_denied"
  } else {
    "validation_failed"
  }
}

///|
test "pattern repair validation builds host-owned dump command" {
  assert_eq(pattern_repair_dump_args("inspect($(node:arg))"), [
    "dump", "--expr", "inspect($(node:arg))",
  ])
}

///|
test "pattern repair validation bounds diagnostics and classifies errors" {
  assert_eq(
    pattern_repair_validation_code("Pattern is not a valid MoonBit expression"),
    "invalid_pattern",
  )
  assert_eq(
    pattern_repair_validation_code("Access is denied"),
    "permission_denied",
  )
  assert_eq(
    pattern_repair_validation_code("unexpected failure"),
    "validation_failed",
  )
  assert_eq(
    pattern_repair_diagnostic(""),
    "Pattern validation failed without a diagnostic.",
  )
}
