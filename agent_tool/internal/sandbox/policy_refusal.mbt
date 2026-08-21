///|
/// The line moonrun prints when its `--wasm-policy` blocks a file or network
/// access, ahead of the error the guest itself sees:
///
/// ```text
/// Sandbox policy blocked file write: "/private/tmp/escape.txt"
/// OSError("@fs.open(): \"/private/tmp/escape.txt\": Permission denied")
/// ```
const PolicyBlockedAccess : String = "Sandbox policy blocked "

///|
/// A refused spawn prints no such line — the guest just sees `EPERM` from the
/// one call a policy refuses this way, so the call itself is the marker.
const PolicyRefusedSpawn : String = "@process.spawn(): Permission denied"

///|
/// Whether `output` shows the moonrun policy refusing something.
///
/// The policy is the other confinement layer from the `sandbox-exec` profiles
/// this module prepares, and the one that exists everywhere: it binds the
/// snippet on every platform, so this is read whether or not a kernel profile
/// was available.
///
/// Recognition is by the runtime's own fixed wording rather than by reasoning
/// about paths, which is what keeps it independent of the roots a policy
/// happens to grant: widening or narrowing the policy cannot make a refusal
/// stop being recognized.
pub fn output_reports_policy_refusal(output : String) -> Bool {
  output.contains(PolicyBlockedAccess) || output.contains(PolicyRefusedSpawn)
}

///|
/// Guidance to append when a run's output shows a policy refusal.
///
/// Two rules produce it — a file access outside the snippet's roots, and a
/// program the spawn allowlist will not start — and a refused spawn carries no
/// path at all, so this names both instead of asserting one. Asserting one is
/// how a refused `@process.spawn` came to be explained as a blocked file write,
/// sending the model to debug paths for a failure that had no path in it.
///
/// It does not list ways to evade the boundary. An earlier wording spelled out
/// renames, copies and temp-then-move as things not to try, which is a worse
/// instruction than the plain one: the reader who had not thought of them now
/// has, and a model that decides to evade is not stopped by having been told the
/// names of the techniques.
///
/// It ends by pointing at the replacement rather than at the boundary, because
/// that is what the refusals in 60 measured trials actually were: `ls`, `cat`,
/// `pwd`, `which`, `sh` — POSIX utilities with a one-line MoonBit form. Two
/// earlier sentences were dropped for saying nothing to that case. One coached
/// reaching a just-built executable through `moon run`, which no trial ever
/// tried; the other said to stay inside the workspace, which is not what a
/// refused `ls` is about. Every access refusal on record was a READ, and reads
/// are now allowed outright, so that half of the message has no live case left.
pub let policy_refusal_feedback : String =
  #|run_moonbit sandbox: that failure is this tool's policy refusing something, not a
  #|filesystem problem to debug — either a read or write left the workspace, or the
  #|program is not on the spawn allowlist. Use the MoonBit replacement for the
  #|utility you reached for, rather than another program.
