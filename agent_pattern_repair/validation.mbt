///|
/// The Host supplies this closed validator configuration to the one-shot
/// subrun. The Agent can choose only a pattern to validate, never a command or
/// arguments outside this fixed `dump --expr` invocation.
const PatternRepairValidatorEnv : String = "OPENSEEK_PATTERN_REPAIR_VALIDATOR"

///|
const MaxPatternValidationDiagnosticUnits : Int = 1000

///|
struct PatternRepairValidator {
  command : String
  prefix_args : Array[String]
} derive(FromJson)

///|
pub extend PatternRepairValidator with FromJson::{from_json}

///|
/// Raised when the Host-provided validator cannot run or rejects the candidate
/// pattern. `Unavailable` means the validator could not be resolved or spawned;
/// `Invalid` carries the parser diagnostic the Agent can use to repair the
/// pattern.
priv suberror PatternValidationError {
  Unavailable
  Invalid(String)
}

///|
fn pattern_repair_validator_from_environment() -> PatternRepairValidator raise PatternValidationError {
  guard @env.get_env_var(PatternRepairValidatorEnv) is Some(raw) else {
    raise Unavailable
  }
  let json = @json.parse(raw) catch { _ => raise Unavailable }
  let validator : PatternRepairValidator = @json.from_json(json) catch {
    _ => raise Unavailable
  }
  if validator.command.trim().is_empty() {
    raise Unavailable
  }
  validator
}

///|
async fn run_pattern_repair_validator(
  validator : PatternRepairValidator,
  pattern~ : String,
  workspace_root~ : String,
) -> Unit {
  let args = validator.prefix_args.copy()
  args.append(["dump", "--expr", pattern, "--strict-check", "--exit-code"])
  let (code, stdout, stderr) = try {
    let (stdin_reader, stdin_writer) = @process.write_to_process()
    stdin_writer.close()
    @process.collect_output(
      validator.command,
      args,
      inherit_env=false,
      extra_env=@env.get_env_vars(),
      stdin=stdin_reader,
      cwd=workspace_root,
      no_console_window=true,
    )
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise Unavailable
  }
  if code != 0 {
    let detail = if !stderr.text().trim().is_empty() {
      stderr.text()
    } else {
      stdout.text()
    }
    let detail = detail.trim().to_owned()
    let diagnostic = if detail.is_empty() {
      "Pattern validation failed without a diagnostic."
    } else if detail.length() > MaxPatternValidationDiagnosticUnits {
      detail[:MaxPatternValidationDiagnosticUnits].to_owned() + "..."
    } else {
      detail
    }
    raise Invalid(diagnostic)
  }
}

///|
async fn validate_pattern_tool_action(
  args : Json,
  workspace_root : String,
  validated_pattern : Ref[String?],
) -> @agent_tool.ToolAction {
  // A failed or superseding validation must invalidate the previous success;
  // submit_pattern_repair is gated on this ref matching its candidate.
  validated_pattern.val = None
  guard args is { "pattern": String(pattern), .. } else {
    return @agent_tool.respond(
      "validate_pattern requires a string pattern.",
      is_error=true,
    )
  }
  if pattern.trim().is_empty() || pattern.length() > MaxPatternChars {
    return @agent_tool.respond(
      "validate_pattern requires a non-empty pattern within the size limit.",
      is_error=true,
    )
  }
  try {
    let validator = pattern_repair_validator_from_environment()
    run_pattern_repair_validator(validator, pattern~, workspace_root~)
    validated_pattern.val = Some(pattern)
    @agent_tool.respond(({ "valid": true } : Json).stringify())
  } catch {
    Unavailable =>
      @agent_tool.respond("Pattern validation is unavailable.", is_error=true)
    Invalid(diagnostic) =>
      @agent_tool.respond(
        ({ "valid": false, "diagnostic": diagnostic } : Json).stringify(),
      )
    error => raise error
  }
}

///|
fn validate_pattern_tool(
  workspace_root : String,
  validated_pattern : Ref[String?],
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="validate_pattern",
    description="Validate one candidate MoonBit structural pattern with the Host-provided moongrep parser. Use it before submitting a candidate; a false result includes a diagnostic to repair.",
    schema=JsonSchema({
      "type": "object",
      "properties": { "pattern": { "type": "string" } },
      "required": ["pattern"],
    }),
    execute=Async(args => {
      validate_pattern_tool_action(args, workspace_root, validated_pattern)
    }),
  )
}
