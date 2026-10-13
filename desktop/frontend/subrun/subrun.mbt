// A sub-run is a child turn the current turn is blocked on. Nothing about it
// is durable: no `session.jsonl` event describes a child's progress, and the
// only thing the record will ever hold is the parent's tool call and, if the
// child finishes normally, its brief. So a lane is status about the run in
// flight, not transcript content — it belongs with the composer's other live
// run state rather than inside the scroller, where it would be a row no
// durable event could ever place.

///|
/// One sub-run in flight: what it was asked, how far it has gotten, and what
/// it is doing right now. Progress is absent until the child has written a
/// durable record; `run` prevents a lane stranded by a lost finish
/// notification from leaking into a later turn.
pub(all) struct Lane {
  id : String
  kind : String
  label : String
  steps : Int32
  activity : String
  run : String?
} derive(Eq, @debug.Debug)

///|
/// The sub-run dock, above the composer: every child this turn is waiting on.
///
/// The step count and activity come from the host reading the child's own
/// record, so they appear only once the child has written something — and
/// never at all for a conversation with no durable session. The lane still
/// renders: that a sub-run is running is worth showing even when its progress
/// is not readable.
///
/// The slot renders even with no lane to show, so the composer's child list
/// keeps a fixed shape while children come and go mid-turn; an empty slot
/// collapses in CSS.
pub fn dock(lanes : Array[Lane]) -> @html.Html {
  @html.div(class="subrun-dock", [ for lane in lanes => lane_view(lane) ])
}

///|
/// What the lane can say about the child's progress right now, as the step
/// cell and the activity cell. Both are absent until the child has written a
/// durable record the host can read, and a lane with nothing readable still
/// says it started rather than rendering an empty row.
fn detail_cells(lane : Lane) -> (String?, String?) {
  let steps = if lane.steps > 0 { Some("step \{lane.steps}") } else { None }
  let activity = if !lane.activity.is_empty() {
    Some(lane.activity)
  } else if steps is None {
    Some("starting…")
  } else {
    None
  }
  (steps, activity)
}

///|
fn lane_view(lane : Lane) -> @html.Html {
  let (steps, activity) = detail_cells(lane)
  let detail : Array[@html.Html] = []
  if steps is Some(text) {
    detail.push(@html.span(class="subrun-step", text))
  }
  if activity is Some(text) {
    detail.push(@html.span(class="subrun-activity", text))
  }
  @html.div(
    class="subrun-lane",
    title="\{lane.kind} \{lane.id}: \{lane.label}",
    [
      @html.span(class="subrun-mark", ""),
      @html.span(class="subrun-name", "\{lane.kind} \{lane.id}"),
      @html.span(class="subrun-detail", detail),
    ],
  )
}

///|
/// The lanes belonging to one open run. A lane whose owner is absent or is a
/// previous run is dropped rather than shown under the turn that followed it.
pub fn owned_by(lanes : Array[Lane], run_id : String) -> Array[Lane] {
  lanes.filter(lane => lane.run is Some(owner) && owner == run_id)
}

///|
pub extend Lane with Debug::{to_repr}

///|
pub extend Lane with Eq::{equal, not_equal}
