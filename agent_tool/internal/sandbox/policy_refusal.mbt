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
/// Names both rules rather than asserting one: a refused spawn carries no path,
/// and reading it as a blocked write once sent the model to debug paths.
///
/// Ends on the replacement because that is what every refusal in 60 measured
/// trials was — `ls`, `cat`, `pwd`, `which`, `sh`. It deliberately lists no ways
/// around the boundary; naming evasion techniques teaches them without stopping
/// anyone.
pub let policy_refusal_feedback : String =
  #|run_moonbit sandbox: that failure is this tool's policy refusing something, not a
  #|filesystem problem to debug — either the program is not on the spawn allowlist, or
  #|the snippet tried to write outside its own `@fs.tmpdir()`. Reach for the
  #|MoonBit replacement of the utility you wanted rather than another program, and
  #|for the file tools to change a file.
