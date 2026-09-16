///|
/// Keep candidate validation bounded and deterministic. The Host chooses the
/// executable and fixed arguments, exposes them to the Agent through the
/// validator tool, and repeats the check authoritatively after submit.
const PatternRepairDumpMaxDiagnosticUnits : Int = 1000

///|
const PatternRepairValidatorEnvironment : String = "OPENSEEK_PATTERN_REPAIR_VALIDATOR"

///|
/// Enable after moongrep's `dump --expr` accepts Pattern metavariables.
const PatternRepairValidationEnabled : Bool = true

///|
fn pattern_repair_provider_args(
  command : String,
  pattern : String,
) -> Array[String] {
  let args = pattern_repair_provider_prefix_args(command)
  args.append(["dump", "--expr", pattern, "--strict-check", "--exit-code"])
  args
}

///|
fn pattern_repair_provider_prefix_args(command : String) -> Array[String] {
  if command == "moonx" ||
    command.has_suffix("/moonx") ||
    command.has_suffix("\\moonx") {
    [MoongrepPackageCoordinate, "--"]
  } else {
    []
  }
}

///|
fn pattern_repair_validator_config(command : String) -> Json {
  {
    "command": command,
    "prefix_args": pattern_repair_provider_prefix_args(command),
  }
}

///|
priv enum PatternRepairValidation {
  PatternRepairValid
  PatternRepairUnavailable
  PatternRepairInvalid(String)
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
        "The semantic-search provider is unavailable.",
      )
    }
    let (code, stdout, stderr) = @processx.collect_output_no_stdin(
      command,
      pattern_repair_provider_args(command, pattern),
      cwd=root.0,
    ) catch {
      error =>
        return PatternRepairInvalid(
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
      PatternRepairInvalid(pattern_repair_diagnostic(detail))
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
test "pattern repair validation preserves the dump command" {
  assert_eq(pattern_repair_provider_args("moonx", "foo()"), [
    MoongrepPackageCoordinate,
    "--",
    "dump",
    "--expr",
    "foo()",
    "--strict-check",
    "--exit-code",
  ])
}

///|
test "pattern repair validator configuration keeps provider ownership in the Host" {
  assert_eq(pattern_repair_validator_config("moonx"), {
    "command": "moonx",
    "prefix_args": [MoongrepPackageCoordinate, "--"],
  })
}

///|
test "pattern repair validation preserves the provider diagnostic" {
  assert_eq(
    pattern_repair_diagnostic("Pattern is not a valid MoonBit expression"),
    "Pattern is not a valid MoonBit expression",
  )
  assert_eq(
    pattern_repair_diagnostic(""),
    "Pattern validation failed without a diagnostic.",
  )
}
