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
/// The always-true half of the guidance appended when a run's output shows a
/// policy refusal.
///
/// Names both rules rather than asserting one: a refused spawn carries no path,
/// and reading it as a blocked write once sent the model to debug paths.
///
/// Ends on the replacement because that is what every refusal in 60 measured
/// trials was — `ls`, `cat`, `pwd`, `which`, `sh`. It deliberately lists no ways
/// around the boundary; naming evasion techniques teaches them without stopping
/// anyone. The one door it may name is the sanctioned one, and only where that
/// door exists — see `policy_refusal_with_escalation`.
pub let policy_refusal_feedback : String =
  #|run_moonbit sandbox: that failure is this tool's policy refusing something, not a
  #|filesystem problem to debug — either the program is not on the spawn allowlist, or
  #|the snippet tried to write outside its own `@fs.tmpdir()`. Reach for the
  #|MoonBit replacement of the utility you wanted rather than another program, and
  #|for the file tools to change a file.

///|
/// The sanctioned way past the line, named AT the line.
///
/// The tool description says this too, but a description is read once at the
/// top of a session and this fires at the moment the decision is being made —
/// which is the only moment it changes anything. Without it the model does
/// what it did in practice: reconstructs the refused command out of allowed
/// parts, silently, having forgotten that asking was available.
///
/// It says "this exact snippet, once" on purpose, twice over. The failure mode
/// of naming an escape at a refusal is that the escape becomes the first move,
/// and pinning the retry to the snippet already written keeps escalating a
/// decision about THIS command rather than a mode to switch into. That same
/// wording is why only a FOREGROUND refusal may carry this: it assumes nothing
/// ran, which is true of a snippet the policy stopped and false of a background
/// job that worked for minutes before tripping over one — telling that job's
/// reader to "retry this exact snippet" misdescribes the state of the world.
let policy_refusal_escalation : String =
  #|If no MoonBit replacement is faithful — the refused program IS the task — you
  #|may retry this exact snippet ONCE with `escalated: true`, which asks the user to
  #|run it with no policy and blocks until they answer. That is the only sanctioned
  #|way past this refusal; do not go looking for a third one.

///|
/// The same guidance for a caller that can offer the sanctioned retry.
///
/// A joined constant rather than a Bool parameter, because the join — and the
/// blank line in it — belongs in one place, and because the only caller that
/// may use it is the one holding an approval channel AND reporting a run that
/// did not happen. `job_output` reads the plain text above: it reports a job
/// that already ran, which this text's "retry this exact snippet" does not
/// describe.
pub let policy_refusal_with_escalation : String = "\{policy_refusal_feedback}\n\n\{policy_refusal_escalation}"
