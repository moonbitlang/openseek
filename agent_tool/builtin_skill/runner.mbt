///|
priv struct SkillCall {
  skill : String
  args : Array[String]?
  cwd : String?
  description : String?
} derive(FromJson)

///|
/// Execute only artifacts named by the host's bundled skill catalog. The
/// catalog and task scope are captured by the host, never decoded from a call.
pub fn definition(
  skills : Array[@agent_skill.BuiltinSkill],
  workspace_root~ : String,
  read_only? : Bool = false,
  scratch_dir? : String,
  worker_sandbox? : @write_scope.WorkerSandbox,
  bg_runtime? : @bgjobs.BgJobRuntime,
  auto_background_after_ms? : Int = 10000,
  foreground_timeout_ms? : Int = 300000,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="run_builtin_skill",
    description="Execute a Wasm skill shipped with OpenSeek. Read its SKILL.md first. Select a listed skill id, not a path. args are passed verbatim. cwd defaults to the workspace. An argument equal to $OUTPUT_DIR or beginning with $OUTPUT_DIR/ expands to this invocation's retained output directory. Supporting files are under OPENSEEK_SKILL_DIR; TMPDIR is writable scratch space. The task's normal permissions apply. Long runs move to background jobs when available.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "skill": { "type": "string", "enum": skills.map(s => s.id).to_json() },
        "args": { "type": "array", "items": { "type": "string" } },
        "cwd": { "type": "string" },
        "description": { "type": "string" },
      },
      "required": ["skill"],
      "additionalProperties": false,
    }),
    execute=Async(arguments => {
      try {
        let call : SkillCall = @json.from_json(arguments)
        guard skills.iter().find_first(s => s.id == call.skill) is Some(skill) else {
          return @agent_tool.respond(
            "unknown builtin skill: \{call.skill}",
            is_error=true,
          )
        }
        run(
          skill,
          call.args.unwrap_or([]),
          workspace_root~,
          cwd?=call.cwd,
          description?=call.description,
          read_only~,
          scratch_dir?,
          worker_sandbox?,
          bg_runtime?,
          auto_background_after_ms~,
          foreground_timeout_ms~,
        )
      } catch {
        error => @agent_tool.respond("builtin skill: \{error}", is_error=true)
      }
    }),
  )
}

///|
async fn run(
  skill : @agent_skill.BuiltinSkill,
  args : Array[String],
  workspace_root~ : String,
  cwd? : String,
  description? : String,
  read_only~ : Bool,
  scratch_dir? : String,
  worker_sandbox? : @write_scope.WorkerSandbox,
  bg_runtime? : @bgjobs.BgJobRuntime,
  auto_background_after_ms~ : Int,
  foreground_timeout_ms~ : Int,
) -> @agent_tool.ToolAction {
  let run_cwd = @workspace_path.resolve_cwd(workspace_root, cwd)
  let output_parent = match bg_runtime {
    Some(runtime) => runtime.output_directory()
    // A child role's scratch lab is deleted before its report reaches the
    // parent. Results must outlive that lab so reported paths remain usable.
    None => None
  }
  let output_dir = match output_parent {
    Some(parent) => {
      let directory = "\{parent}/skill-\{@uuid.v7()}"
      @fs.mkdir(directory)
      directory
    }
    None => @fs.tmpdir(prefix="openseek-skill-output-")
  }
  let args = args.map(arg => {
    if arg == "$OUTPUT_DIR" {
      output_dir
    } else if arg.strip_prefix("$OUTPUT_DIR/") is Some(relative) {
      "\{output_dir}/\{relative}"
    } else {
      arg
    }
  })
  let dir = @fs.tmpdir(prefix="openseek-skill-")
  let mut handed_off = false
  defer (if !handed_off {
    @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
  })
  let tmp = "\{dir}/tmp"
  @fs.mkdir(tmp)
  // Apply the same environment provisioning as a normal hosted Wasm run:
  // policy copies permitted host values, overrides TMPDIR, and clears stale
  // workflow/PTC capabilities. No model-provided environment or policy path.
  let policy = @wasm_policy.wasm_policy_document(
    tmp_dir=tmp,
    extra_roots=[output_dir, ..scratch_dir.map(dir => [dir]).unwrap_or([])],
    inject=Map([
      ("OPENSEEK_SKILL_DIR", skill.root),
      ("OPENSEEK_SKILL_OUTPUT_DIR", output_dir),
    ]),
    spawnable=None,
  )
  let policy_path = "\{dir}/policy.json"
  @fs.write_file(policy_path, policy.stringify(), create_mode=CreateNew)
  let stdin_path = "\{dir}/stdin.empty"
  @fs.write_file(stdin_path, "", create_mode=CreateNew)
  let argv = ["--policy", policy_path, skill.wasm, "--", ..args]
  let command = @sandbox.confine(
    Exec("moonrun", argv),
    workspace_root~,
    read_only~,
    worker_sandbox?,
    profile_path="\{dir}/source-write.sb",
    writable_subtree=scratch_dir.unwrap_or(dir),
  )
  let (program, argv) = match command {
    Some(command) => (command.program(), command.args())
    None => ("moonrun", argv)
  }
  @async.with_task_group(group => {
    let runtime = bg_runtime.unwrap_or_else(() => {
      BgJobRuntime(AgentTaskScope(group), spill_dir=dir)
    })
    let exec = runtime.spawn_foreground_retained(
      program,
      argv,
      run_cwd,
      48000,
      stdin=@process.redirect_from_file(stdin_path),
    )
    defer (if !handed_off {
      @async.protect_from_cancel(() => {
        exec.request_stop()
        exec.wait()
        exec.discard()
      })
    })
    let finished = @async.with_timeout_opt(
      if bg_runtime is Some(_) {
        auto_background_after_ms
      } else {
        foreground_timeout_ms
      },
      () => exec.wait(),
    )
    if finished is None && bg_runtime is Some(_) {
      let job_id = runtime.adopt(
        exec,
        command="builtin:\{skill.id}",
        description?,
        sandboxed_command?=command,
        read_only_review=read_only,
        moonrun_policy_active=true,
        on_terminal=() => {
          @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
        },
      )
      handed_off = true
      return @agent_tool.respond(
        "builtin:\{skill.id} is running as job \{job_id}. Use job_output to read its output or job_stop to stop it. Outputs: \{output_dir}",
        brief="builtin:\{skill.id} → bg \{job_id}",
      )
    }
    if finished is None {
      exec.request_stop()
      exec.wait()
    }
    if exec.output_error() is Some(error) {
      fail(error)
    }
    let status = match exec.exit_code() {
      Some(code) => "exit=\{code}"
      None => "stopped"
    }
    let mut output = "\{status}\nOutputs: \{output_dir}\n\{exec.head()}"
    let mut is_error = exec.exit_code() != Some(0) || finished is None
    if finished is None {
      output += "\n[builtin skill exceeded its foreground time limit]"
    }
    if exec.output_truncated() || exec.over_inline_cap() {
      output += "\n[builtin skill stopped after exceeding the output limit]"
      is_error = true
    }
    if exec.had_invalid_utf8() {
      output += "\n[output contained non-UTF-8 bytes]"
    }
    if is_error {
      if command is Some(command) && command.output_reports_denial(output) {
        output += "\n\{command.denial_feedback()}"
      } else if @sandbox.output_reports_policy_refusal(output) {
        output += "\n\{@sandbox.policy_refusal_feedback}"
      }
    }
    @agent_tool.respond(output, is_error~, brief="builtin:\{skill.id}")
  })
}
