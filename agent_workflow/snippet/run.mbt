// The one entry point a snippet calls.
//
// Everything the desktop needs is a SIDE EFFECT of running here: children get
// durable sessions, completions append to the journal, and lifecycle lines
// stream to the sidecar. The snippet author writes the shape of the work and
// nothing else — no session ids, no paths, no ordinals, no budget.
//
// That is deliberate. The alternative — teaching the model to pass these
// itself — would put the coordinates that make a run visible into the same
// text that decides what the run does, where a plausible-looking wrong value
// silently produces an invisible workflow.

///|
/// Run `body` with a workflow wired to the injected coordinates.
///
/// `max_concurrent` bounds how many children run at once. The LIFETIME launch
/// cap is not a parameter: it is the reserved block, which the runner enforces
/// by refusing calls past its end. A snippet cannot widen it, because it
/// cannot mint an ordinal it was not given.
///
/// The journal is file-backed and append-only, so a reader tailing it sees
/// each completion as it lands. `phase` is tracked here rather than read from
/// the journal because `Workflow::phase` is a live setting that the sidecar's
/// `started` lines need before any entry exists to carry it.
pub async fn[T] run(
  spec : Injected,
  body : async (@workflow.Workflow) -> T,
  max_concurrent? : Int = 4,
) -> T {
  let phase : Ref[String?] = Ref(None)
  let journal = @workflow.Journal::load(spec.journal_path)
  let wf = @workflow.Workflow(
    runner=runner(spec, phase~),
    max_concurrent~,
    journal~,
    on_event=event => {
      match event {
        // The only event whose information is not already in the journal or
        // the sidecar: a phase is declared BEFORE the calls it groups, and
        // nothing else records it until one of them finishes.
        PhaseStarted(title) => phase.val = Some(title)
        _ => ()
      }
    },
  )
  body(wf)
}

///|
/// The journal this snippet writes, for a caller that wants to read its own
/// ledger back (a summary line, a cost figure) rather than leave it to the
/// viewer.
pub fn Injected::journal_path(self : Injected) -> String {
  self.journal_path
}
