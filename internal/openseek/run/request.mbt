///|
/// How `run` learns what to do.
priv enum InputMode {
  /// The task is the command line's words.
  Text
  /// One JSON request is read from stdin through EOF. EOF only ends the input.
  Batch
  /// One JSON request is read as a line, for a parent that launched this run.
  /// The parent keeps stdin open; closing it later cancels the run.
  Managed
} derive(Eq)

///|
fn input_mode(matches : @argparse.Matches) -> InputMode raise {
  let json = match matches.values.get("input-format") {
    Some(["json", ..]) => true
    Some(["text", ..]) | None => false
    Some([other, ..]) =>
      fail("--input-format must be text or json, not \{other}")
    Some([]) => false
  }
  let managed = matches is { flags: { "cancel-on-stdin-eof": true, .. }, .. }
  match (json, managed) {
    (false, true) => fail("--cancel-on-stdin-eof needs --input-format json")
    (false, false) => Text
    (true, false) => Batch
    (true, true) => Managed
  }
}

///|
/// What the run does: the general agent on a task, or a preset on its input.
priv enum Profile {
  General(task~ : String)
  Preset(kind~ : Kind, name~ : String, input~ : Json)
}

///|
/// A run's request, read and checked before anything is created: no workspace,
/// session or model call exists yet when a bad request is refused.
priv struct Invocation {
  request_id : String?
  profile : Profile
  /// The request's step ceiling; see `resolved_max_steps`.
  requested_max_steps : Int?
}

///|
/// The preset's name when this run is one, for the result's `kind`.
fn Invocation::kind_name(self : Invocation) -> String? {
  match self.profile {
    General(_) => None
    Preset(name~, ..) => Some(name)
  }
}

///|
/// Read the run's request: the command-line task in text mode, else one JSON
/// request from stdin.
async fn read_invocation(
  matches : @argparse.Matches,
  mode : InputMode,
) -> Invocation {
  let cli_kind = match matches.values.get("kind") {
    Some([kind, ..]) => Some(kind)
    _ => None
  }
  let has_task_words = matches.values.get("task") is Some(words) &&
    words.any(word => !word.is_blank())
  let text = match mode {
    Text => {
      if cli_kind is Some(_) {
        fail("--kind needs --input-format json: a preset reads a JSON request")
      }
      return {
        request_id: None,
        profile: General(task=@options.task_text(matches)),
        requested_max_steps: None,
      }
    }
    Batch | Managed if has_task_words =>
      fail(
        "a task on the command line cannot be combined with --input-format json",
      )
    Batch => @stdio.stdin.read_all().text()
    Managed =>
      match @stdio.stdin.read_until("\n") {
        Some(line) => line
        None => fail("stdin closed before a request arrived")
      }
  }
  let json = @json.parse(text.trim()) catch {
    error => fail("the request on stdin is not JSON: \{error}")
  }
  let request = @openseek_protocol.parse_run_request(json) catch {
    UnsupportedVersion(version) =>
      fail("unsupported request version \{version}")
    Malformed(field) => fail("malformed request: `\{field}`")
    Unsupported(field) =>
      fail("this engine does not support the request's `\{field}`")
  }
  let name = match (cli_kind, request.kind) {
    (Some(flag), Some(requested)) if flag != requested =>
      fail("--kind \{flag} does not match the request's kind \{requested}")
    (Some(name), _) | (None, Some(name)) => name
    (None, None) => "general"
  }
  let profile = if name == "general" {
    guard request.input is { "task": String(task), .. } && !task.is_blank() else {
      fail("a general request's input needs a non-empty `task`")
    }
    General(task=task.trim().to_owned())
  } else {
    guard Kind::parse(name) is Some(kind) else { fail("unknown kind: \{name}") }
    Preset(kind~, name~, input=request.input)
  }
  {
    request_id: request.request_id,
    profile,
    requested_max_steps: request.max_steps,
  }
}

///|
/// The step ceiling a run asked for, by precedence: an explicit `--max-steps`
/// on the command line (the operator's word), else the request's ceiling, else
/// `OPENSEEK_MAX_STEPS`. The environment ranks below the request because it is
/// a standing default, not a word about this call. `None` leaves the run
/// bounded by its own default.
fn resolved_max_steps(
  matches : @argparse.Matches,
  requested : Int?,
) -> Int? raise {
  let configured = @options.max_steps(matches)
  if @options.explicitly_provided(matches, "max-steps") {
    return configured
  }
  match requested {
    Some(steps) => Some(steps)
    None => configured
  }
}

///|
/// Hold the workspace's general-child lease for as long as the returned file
/// stays open, or fail when another delegated general run holds it. Only one
/// write-capable general child may work in a workspace at a time; a parallel
/// writer should be a `worker`, with its own worktree. The lease is an OS lock,
/// so a crashed holder releases it with its process.
async fn acquire_general_child_lease(workspace_root : String) -> @fs.File {
  let dir = "\{workspace_root}/.openseek"
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let file = @fs.open(
    "\{dir}/general-child.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  errdefer file.close()
  guard file.try_lock(Exclusive) else {
    fail(
      "another delegated general run is already working in \{workspace_root}; run a worker for parallel writes",
    )
  }
  file
}
