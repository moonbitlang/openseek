///|
/// Keep candidate validation bounded and deterministic. The Agent must never
/// choose the executable or invoke this command directly; the host owns both.
const PatternRepairDumpMaxDiagnosticUnits : Int = 1000

///|
/// Enable after moongrep's `dump --expr` accepts Pattern metavariables.
const PatternRepairValidationEnabled : Bool = true

///|
fn pattern_repair_provider_args(
  command : String,
  pattern : String,
) -> Array[String] {
  let args : Array[String] = if command == "moonx" ||
    command.has_suffix("/moonx") ||
    command.has_suffix("\\moonx") {
    [MoongrepPackageCoordinate, "--"]
  } else {
    []
  }
  args.append(["dump", "--expr", pattern, "--exit-code"])
  args
}

///|
priv enum PatternRepairValidation {
  PatternRepairValid
  PatternRepairUnavailable
  PatternRepairInvalid(String, String)
}

///|
async fn validate_pattern_repair_candidate(
  root : @pathx.Absolute,
  pattern : String,
) -> PatternRepairValidation {
  if !PatternRepairValidationEnabled {
    PatternRepairUnavailable
  } else {
    guard moongrep_command() is Some(command) else {
      return PatternRepairInvalid(
        "moongrep_unavailable", "The semantic-search provider is unavailable.",
      )
    }
    let (code, stdout, stderr) = @processx.collect_output_no_stdin(
      command,
      pattern_repair_provider_args(command, pattern),
      cwd=root.0,
    ) catch {
      error =>
        return PatternRepairInvalid(
          "validation_failed",
          "Cannot validate Pattern Repair candidate: \{error}",
        )
    }
    if code == 0 {
      PatternRepairValid
    } else {
      let detail = if !stderr.text().trim().is_empty() {
        stderr.text()
      } else {
        stdout.text()
      }
      PatternRepairInvalid(
        pattern_repair_validation_code(detail),
        pattern_repair_diagnostic(detail),
      )
    }
  }
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
test "pattern repair validation preserves the future dump command" {
  assert_eq(pattern_repair_provider_args("moonx", "foo()"), [
    MoongrepPackageCoordinate,
    "--",
    "dump",
    "--expr",
    "foo()",
    "--exit-code",
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
