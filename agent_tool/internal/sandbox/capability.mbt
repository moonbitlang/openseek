///|
/// The command to prepare for source-write-sandboxed execution.
///
/// `Shell` runs command text through the platform shell. `Exec` runs a program
/// with an already-tokenized argument vector and introduces no shell.
pub(all) enum Command {
  Shell(String)
  Exec(String, Array[String])
}

///|
/// One prepared source-write-sandboxed invocation. Its process command and
/// denial subjects stay together so output is always classified against the
/// profile that produced it.
struct SandboxedCommand {
  /// Executable to spawn for this prepared invocation. It is the first half of
  /// the process command and must be passed together with `args`. When sandbox
  /// enforcement is available, this is the platform's `sandbox-exec` binary.
  program : String
  /// Companion argument vector for `program`: the generated profile followed
  /// by either the platform-shell invocation or the requested `Exec`
  /// program/argv. For example, `Shell("moon check")` prepares approximately
  /// `program = "/usr/bin/sandbox-exec"` with
  /// `args = ["-p", "<profile>", "sh", "-c", "moon check"]` on macOS.
  args : Array[String]
  /// True only for the ordinary source-readonly profile with no writable
  /// subtree. A trusted source writer can escape this profile by running as a
  /// standalone shell command; worker and scratch-lab profiles cannot.
  plain_source_readonly : Bool
  /// The paths a denial from this profile may name — protected directories and
  /// basenames — which is how one is told apart from a permission error this
  /// sandbox did not cause. Derived from the same profile encoded in `args`, so
  /// denial reporting cannot use metadata from another run.
  denial_subjects : Array[String]
}

///|
/// Prepare `command` under the source-write sandbox for `workspace_root`, or
/// return `None` when this process cannot enforce one — `sandbox-exec` missing,
/// the availability probe failing, or a nested sandbox that forbids
/// re-sandboxing. `None` means exactly "enforcement unavailable"; the fallback
/// decision stays with the caller, explicit at the call site. Invalid input —
/// an unresolvable `workspace_root`, or a `writable_subtree` that covers the
/// root — raises instead, so misconfiguration cannot silently disable
/// protection.
///
/// The root is resolved to its real path here, because the kernel matches
/// profile rules against realpaths. The rules are built from the tree as it
/// exists now — renaming the root or subtree afterwards makes them stale, so
/// prepare the command close to where it runs.
///
/// `writable_subtree` re-allows writes below one directory — a scratch lab or
/// throwaway build directory — via a last-match-wins allow rule. It is resolved
/// too; when resolution fails the unresolved path is used, which can only
/// under-allow, never over-allow.
pub async fn SandboxedCommand::create_if_available(
  workspace_root : String,
  command : Command,
  writable_subtree? : String,
) -> SandboxedCommand? {
  // Inputs are validated BEFORE the availability probe, so a caller bug is
  // reported identically on every platform instead of hiding behind `None`
  // wherever enforcement happens to be unavailable.
  let real_root = @fs.realpath(workspace_root)
  let subtree = match writable_subtree {
    Some(dir) => {
      let real_dir = @fs.realpath(dir) catch {
        error if @async.is_being_cancelled() => raise error
        _ => dir
      }
      let normalized = @workspace_path.strip_trailing_slash(
        @path.Path(real_dir).normalize().to_string(),
      )
      // A subtree at or above the root would re-allow every source write the
      // profile exists to deny. That is never a scratch dir; it is a caller
      // bug, and failing open on it would be invisible.
      if @workspace_path.is_under_workspace_root(normalized, real_root) {
        fail("writable_subtree covers the workspace root")
      }
      Some(normalized)
    }
    None => None
  }
  guard sandbox_exec_available() else { return None }
  let data = source_write_readonly_profile_data(
    real_root,
    writable_lab?=subtree,
  )
  let args = match command {
    Shell(cmd) => sandbox_exec_args(data.profile, cmd)
    Exec(program, args) => ["-p", data.profile, program, ..args]
  }
  Some({
    program: SandboxExecPath,
    args,
    // Copied: the profile cache hands out its own array, and this command must
    // keep classifying with the subjects of the profile it actually runs under.
    plain_source_readonly: subtree is None,
    denial_subjects: data.denial_subjects.copy(),
  })
}

///|
/// The executable of this prepared invocation.
pub fn SandboxedCommand::program(self : SandboxedCommand) -> String {
  self.program
}

///|
/// A copy of this prepared invocation's argument vector.
pub fn SandboxedCommand::args(self : SandboxedCommand) -> Array[String] {
  self.args.copy()
}

///|
/// Whether `output` contains a likely protected-source write denial from this
/// command. Recognition is heuristic and line-oriented: `true` is strong
/// evidence, not proof, and unrelated permission errors are ignored.
pub fn SandboxedCommand::output_reports_denial(
  self : SandboxedCommand,
  output : String,
) -> Bool {
  source_write_denied_in_text(output, self.denial_subjects)
}

///|
/// The guidance to append when this command's output reports a denial. It comes
/// from the prepared command that classified the output, not from a global a
/// caller picks by hand, so the text can never describe a profile other than the
/// one that actually refused.
pub fn SandboxedCommand::denial_feedback(_self : SandboxedCommand) -> String {
  source_write_denial_feedback
}

///|
/// Whether this command uses the ordinary source-readonly profile, where a
/// normally trusted source writer may succeed when retried by itself.
pub fn SandboxedCommand::allows_standalone_trusted_writer(
  self : SandboxedCommand,
) -> Bool {
  self.plain_source_readonly
}
