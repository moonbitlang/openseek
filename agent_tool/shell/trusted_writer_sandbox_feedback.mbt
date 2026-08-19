///|
/// `moon info` identifies its denied final copy precisely enough to recommend
/// retrying that trusted writer alone. Other denials keep the generic edit
/// guidance because a compound command does not reveal which segment wrote.
fn shell_sandbox_denial_feedback(
  standalone_trusted_writer_allowed : Bool,
  read_only_review : Bool,
  output : String,
) -> String {
  let lines = output.split("\n")
  let moon_copy_denied = lines.any(line => {
    line.contains("Failed to copy generated mbti file") &&
    line.contains("pkg.generated.mbti: Operation not permitted")
  })
  let another_permission_denial = lines.any(line => {
    (
      line.contains("Operation not permitted") ||
      line.contains("operation not permitted") ||
      line.contains(": Permission denied") ||
      line.contains("Permission denied:")
    ) &&
    !(line.contains("Failed to copy generated mbti file") &&
    line.contains("pkg.generated.mbti: Operation not permitted"))
  })
  if !moon_copy_denied || another_permission_denial {
    return SandboxSourceWriteFeedback
  }
  if read_only_review {
    return (
      #|shell sandbox: `moon info` ran inside a command too complex for the read-only
      #|review guard to classify, and its generated interface copy was blocked. This
      #|shell is in read-only review mode, where standalone `moon info` is intentionally
      #|blocked. Do not retry it here; use non-mutating checks such as `moon check` or
      #|`moon test`, and report that interface regeneration must run outside review mode.
    )
  }
  if !standalone_trusted_writer_allowed {
    return SandboxSourceWriteFeedback
  }
  (
    #|shell sandbox: `moon info` was not recognized as a standalone static command,
    #|so the request ran read-only and its generated interface copy was blocked.
    #|Run `moon info` in its own shell call. Keep literal arguments, but replace shell
    #|variables, substitutions, and globs with their concrete literal values. To filter
    #|output, redirect that call to a temporary file outside the workspace source tree,
    #|then inspect the file in a separate shell call.
  )
}
