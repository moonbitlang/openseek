///|
/// The write confinement of a worker subagent's shell, carried from the
/// worker controller (which computes the canonical geometry at provision
/// time) into every launch. When present, shell classification is bypassed:
/// every command — including classes the normal registry trusts to run
/// unsandboxed — launches under the worker write profile, which denies the
/// repository's shared surfaces (`deny_roots`: the canonical common git dir
/// plus every enumerated worktree root) and re-allows only the worker's own
/// tree and its private git admin dir. All paths must be canonical
/// (realpath'd): the kernel matches profile rules against realpaths.
///
/// On platforms without sandbox-exec the kernel layer is absent and the
/// static confinement floor (`worker_confinement_blocks`) is the only guard —
/// the same best-effort posture as the rest of the sandbox stack there.
pub(all) struct WorkerSandbox {
  deny_roots : Array[String]
  worker_root : String
  worker_admin_dir : String
}

///|
/// The static confinement floor for worker mode: block, before launch, the
/// command shapes that OBVIOUSLY leave the worker tree, with an explanation a
/// kernel denial cannot give. Admission requires every resolvable cwd
/// interpretation to stay inside the worker root: the canonicalized base cwd,
/// every statically-spelled `cd` destination (including `--`, wrapper, bare,
/// and `-` forms), and every `git -C`/`--work-tree` operand — resolved
/// against every candidate cwd the chain may be in, since a `cd` may fail at
/// runtime and a `cd` inside a pipeline runs in a subshell. Truly
/// unresolvable operands (substitutions, variables) stay admitted — on macOS
/// the kernel profile is the enforcement; this floor exists for error
/// quality and for platforms without one.
async fn worker_confinement_blocks(
  parsed : @shell_parse.ParseResult,
  base_cwd~ : String,
  worker_root~ : String,
) -> String? {
  // Containment is CHECKED on canonical paths (an in-tree symlink pointing
  // elsewhere must not pass), but cwd TRACKING uses the lexical spelling:
  // sh's cd is logical — `cd ..` operates on the PWD text, so `w/link/..`
  // is `w` at runtime even when `link` resolves elsewhere. Mixing the two
  // (canonical candidates, lexical `..`) mis-predicts sh.
  guard @workspace_path.is_under_workspace_root(
    worker_root,
    canonicalize_existing(base_cwd),
  ) else {
    return Some("the command runs outside your worker tree (cwd \{base_cwd})")
  }
  worker_cd_escapes(
    parsed,
    base_cwd=@path.Path(base_cwd).normalize().to_string(),
    worker_root~,
  )
}

///|
/// Scan chained commands for static escapes, tracking the SET of candidate
/// cwds along the chain: a plain `cd` adds its destination but keeps the old
/// cwd as a candidate (the `cd` may fail at runtime), and a `cd` that is part
/// of a pipeline contributes nothing (it runs in a subshell). An operand
/// escapes when its resolution against ANY candidate leaves the worker root.
async fn worker_cd_escapes(
  parsed : @shell_parse.ParseResult,
  base_cwd~ : String,
  worker_root~ : String,
) -> String? {
  guard parsed is Simple(commands) else { return None }
  // Candidates hold LEXICAL cwd spellings (sh's logical cd semantics);
  // containment checks canonicalize on the spot. `suspended` holds the
  // pre-cd cwds dropped by an `&&`-clearing: a failed cd skips the `&&`
  // chain but the shell REJOINS at the next `;`/`||` from the pre-cd cwd,
  // so those spellings come back into play there.
  let candidates : Array[String] = [base_cwd]
  let suspended : Array[String] = []
  for position, command in commands {
    let argv = command.argv
    match command.separator_before {
      Some(";") | Some("||") => {
        for old in suspended {
          if !candidates.contains(old) {
            candidates.push(old)
          }
        }
        suspended.clear()
      }
      _ => ()
    }
    let in_pipeline = command.separator_before == Some("|") ||
      (
        position + 1 < commands.length() &&
        commands[position + 1].separator_before == Some("|")
      )
    // The effective command name skips wrappers (`command`, `env`), so
    // `command cd ..` is still a cwd change.
    match command.command_index() {
      Some(index) if argv[index] == "cd" => {
        match cd_operand(argv, index) {
          CdTo(operand) => {
            // Resolve against EVERY candidate cwd. Containment is checked on
            // the canonicalized location; the LEXICAL spelling is what a
            // successful cd contributes as a future cwd (sh's `..` is
            // logical). A resolution is viable only when its canonical
            // location is an EXISTING DIRECTORY — sh's cd fails on a file or
            // a missing path, so those never become cwds.
            let viable : Array[String] = []
            let mut interpretations = 0
            for cwd in candidates {
              match resolve_worker_operand(cwd, operand) {
                Some(resolved) => {
                  interpretations += 1
                  let canonical = canonicalize_if_exists(resolved)
                  guard @workspace_path.is_under_workspace_root(
                    worker_root,
                    canonical.unwrap_or(resolved),
                  ) else {
                    return Some("`cd \{operand}` leaves your worker tree")
                  }
                  match canonical {
                    Some(real) =>
                      if path_is_directory(real) && !viable.contains(resolved) {
                        viable.push(resolved)
                      }
                    None => ()
                  }
                }
                None => ()
              }
            }
            // Candidate propagation (outside a pipeline; a pipeline cd runs
            // in a subshell and moves nothing). Under `&&`, the immediately
            // chained command runs only when the cd SUCCEEDED, so its
            // reachable cwds are the viable destinations — the pre-cd cwds
            // move to `suspended` (a failed cd's continuation REJOINS at the
            // next `;`/`||`, where they merge back; dropping them outright
            // admitted a real escape). Under `;`/`||` the cd may have failed
            // in place, so the old cwds stay candidates alongside the
            // destinations. This is a floor, not an interpreter — the kernel
            // profile remains the enforcement where one exists.
            if !in_pipeline {
              let next_is_and = position + 1 < commands.length() &&
                commands[position + 1].separator_before == Some("&&")
              if next_is_and && interpretations > 0 && !viable.is_empty() {
                for old in candidates {
                  if !suspended.contains(old) {
                    suspended.push(old)
                  }
                }
                candidates.clear()
              }
              for destination in viable {
                if !candidates.contains(destination) {
                  candidates.push(destination)
                }
              }
            }
          }
          CdHome =>
            // Bare `cd` goes to $HOME — never the worker tree.
            return Some("`cd` (to $HOME) leaves your worker tree")
          CdBack =>
            // `cd -` returns to $OLDPWD, which this scan cannot know; the
            // quantifier is "every interpretation provably inside".
            return Some("`cd -` targets an unknowable directory")
          CdUnresolvable => ()
        }
        continue
      }
      _ => ()
    }
    for index, arg in argv {
      let operand = if arg == "-C" || arg == "--work-tree" {
        if index + 1 < argv.length() {
          Some(argv[index + 1])
        } else {
          None
        }
      } else if arg.has_prefix("--work-tree=") {
        arg.view(start_offset="--work-tree=".length()).to_owned() |> Some
      } else {
        None
      }
      match operand {
        Some(op) =>
          for cwd in candidates {
            match resolve_worker_operand(cwd, op) {
              Some(resolved) =>
                if !@workspace_path.is_under_workspace_root(
                    worker_root,
                    canonicalize_existing(resolved),
                  ) {
                  return Some("`\{arg} \{op}` points outside your worker tree")
                }
              None => ()
            }
          }
        None => ()
      }
    }
  }
  None
}

///|
priv enum CdOperand {
  CdTo(String)
  CdHome
  CdBack
  CdUnresolvable
}

///|
/// The destination of a `cd` at `argv[index]`: skip `-P`/`-L` flags and a
/// `--` separator; a bare `cd` is $HOME; `cd -` is $OLDPWD.
fn cd_operand(argv : Array[String], index : Int) -> CdOperand {
  let mut cursor = index + 1
  while cursor < argv.length() && (argv[cursor] == "-P" || argv[cursor] == "-L") {
    cursor += 1
  }
  if cursor < argv.length() && argv[cursor] == "--" {
    cursor += 1
  }
  if cursor >= argv.length() {
    return CdHome
  }
  let operand = argv[cursor]
  if operand == "-" {
    return CdBack
  }
  if operand.has_prefix("-") {
    // An unrecognized option shape; sh would reject or reinterpret it —
    // nothing this scan can resolve.
    return CdUnresolvable
  }
  CdTo(operand)
}

///|
/// Lexically resolve one statically-spelled operand against `cwd`; `None`
/// for shapes only the shell can evaluate (substitutions, variables, `~`).
fn resolve_worker_operand(cwd : String, operand : String) -> String? {
  if operand.contains("$") || operand.contains("`") || operand.has_prefix("~") {
    return None
  }
  let joined = if @path.Path(operand).is_absolute() {
    operand
  } else {
    "\{cwd}/\{operand}"
  }
  Some(@path.Path(joined).normalize().to_string())
}

///|
/// Best-effort canonicalization for containment checks: realpath when the
/// path exists (resolving in-tree symlinks that point elsewhere), the
/// lexically-normalized spelling otherwise (a nonexistent directory cannot
/// be a running process's cwd either).
async fn canonicalize_existing(path : String) -> String {
  canonicalize_if_exists(path).unwrap_or(
    @path.Path(path).normalize().to_string(),
  )
}

///|
/// `Some(realpath)` when the path exists, `None` otherwise.
async fn canonicalize_if_exists(path : String) -> String? {
  Some(@fs.realpath(path)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}
