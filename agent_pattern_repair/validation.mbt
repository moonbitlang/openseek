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
fn pattern_repair_validator_from_environment() -> Result[
  PatternRepairValidator,
  String,
] {
  guard @env.get_env_var(PatternRepairValidatorEnv) is Some(raw) else {
    return Err("Pattern validation is unavailable.")
  }
  let json = @json.parse(raw) catch {
    _ => return Err("Pattern validation is unavailable.")
  }
  let validator : PatternRepairValidator = @json.from_json(json) catch {
    _ => return Err("Pattern validation is unavailable.")
  }
  if validator.command.trim().is_empty() {
    Err("Pattern validation is unavailable.")
  } else {
    Ok(validator)
  }
}

///|
async fn run_pattern_repair_validator(
  validator : PatternRepairValidator,
  pattern : String,
  workspace_root : String,
) -> Result[String, String] {
  let args = validator.prefix_args.copy()
  args.append(["dump", "--expr", pattern, "--strict-check", "--exit-code"])
  let (code, stdout, stderr) = @async.with_task_group(group => {
    let (stdin_reader, stdin_writer) = @process.write_to_process()
    let (stdout_reader, child_stdout) = @process.read_from_process()
    let (stderr_reader, child_stderr) = @process.read_from_process()
    let process = @process.spawn(
      group,
      validator.command,
      args,
      inherit_env=false,
      extra_env=@env.get_env_vars(),
      stdin=stdin_reader,
      stdout=child_stdout,
      stderr=child_stderr,
      cwd=workspace_root,
      no_console_window=true,
      no_wait=true,
    )
    errdefer {
      stdin_writer.close()
      process.cancel()
    }
    stdin_writer.close()
    let stdout_task = group.spawn(() => {
      defer stdout_reader.close()
      stdout_reader.read_all().text() catch {
        _ => ""
      }
    })
    let stderr_task = group.spawn(() => {
      defer stderr_reader.close()
      stderr_reader.read_all().text() catch {
        _ => ""
      }
    })
    let code = process.wait()
    (code, stdout_task.wait(), stderr_task.wait())
  }) catch {
    _ => return Err("Pattern validation is unavailable.")
  }
  if code == 0 {
    Ok("")
  } else {
    let detail = if !stderr.trim().is_empty() { stderr } else { stdout }
    let detail = detail.trim().to_owned()
    let diagnostic = if detail.is_empty() {
      "Pattern validation failed without a diagnostic."
    } else if detail.length() > MaxPatternValidationDiagnosticUnits {
      detail[:MaxPatternValidationDiagnosticUnits].to_owned() + "..."
    } else {
      detail
    }
    Err(diagnostic)
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
  let validator = match pattern_repair_validator_from_environment() {
    Ok(validator) => validator
    Err(message) => return @agent_tool.respond(message, is_error=true)
  }
  match run_pattern_repair_validator(validator, pattern, workspace_root) {
    Ok(_) => {
      validated_pattern.val = Some(pattern)
      @agent_tool.respond(({ "valid": true } : Json).stringify())
    }
    Err(diagnostic) =>
      @agent_tool.respond(
        ({ "valid": false, "diagnostic": diagnostic } : Json).stringify(),
      )
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
