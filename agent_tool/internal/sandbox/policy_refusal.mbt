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
pub let policy_refusal_feedback : String =
  #|run_moonbit sandbox: the failure above is this tool's snippet policy refusing
  #|something — not a filesystem or permissions problem to debug. Either the snippet's
  #|own read or write landed OUTSIDE the workspace (inside it everything is allowed,
  #|including source files), or it tried to start a program the spawn allowlist does
  #|not hold — note that an executable this run just built is never spawnable by name,
  #|so reach it with `moon run`, or exercise the code through `moon test`.
  #|Do NOT try to work around the block from inside a program (renames, copies,
  #|temp-then-move, or other sandbox escapes); stay under the workspace, and if what you
  #|need is genuinely outside it, say so rather than routing around the boundary.
