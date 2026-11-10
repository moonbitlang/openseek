///|
/// Keep candidate validation bounded and deterministic. The Host chooses the
/// executable and fixed arguments, exposes them to the Agent through the
/// validator tool, and repeats the check authoritatively after submit.
const PatternRepairDumpMaxDiagnosticUnits : Int32 = 1000

///|
const PatternRepairValidatorEnvironment : String = "OPENSEEK_PATTERN_REPAIR_VALIDATOR"

///|
/// Enable after moongrep's `dump --expr` accepts Pattern metavariables.
const PatternRepairValidationEnabled : Bool = true

///|
fn pattern_repair_provider_args(pattern : String) -> Array[String] {
  @search.moongrep_args([
    "dump", "--expr", pattern, "--strict-check", "--exit-code",
  ])
}

///|
fn pattern_repair_validator_config(command : String) -> Json {
  { "command": command, "prefix_args": @search.moongrep_args([]) }
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
  provider : @moonbit.ResolvedMoonxProvider,
) -> PatternRepairValidation {
  if !PatternRepairValidationEnabled {
    PatternRepairUnavailable
  } else {
    let result = @processx.collect_output_no_stdin(
      provider.command,
      pattern_repair_provider_args(pattern),
      extra_env=provider.environment,
      inherit_env=false,
      cwd=root.0,
    ) catch {
      error =>
        return PatternRepairInvalid(
          "Cannot validate Pattern Repair candidate: \{error}",
        )
    }
    let code = result.exit_code
    if code == 0 {
      PatternRepairValid
    } else {
      let detail = if !result.stderr_text().trim().is_empty() {
        result.stderr_text()
      } else {
        result.stdout_text()
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
  assert_eq(pattern_repair_provider_args("foo()"), [
    @search.MoongrepPackageCoordinate,
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
    "prefix_args": [@search.MoongrepPackageCoordinate, "--"],
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
