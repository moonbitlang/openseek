///|
/// One row of the waterfall: where its bar starts and how wide it is on the
/// shared time axis, in percent.
///
/// `left_percent` and `width_percent` are positions inside the run's window, so
/// a renderer only needs to place a bar inside a container rather than reason
/// about milliseconds. A span that is still running is laid out against the
/// caller's clock, which is what makes the bar grow instead of sitting at zero.
pub(all) struct WaterfallRow {
  span : TrajectorySpan
  left_percent : Double
  width_percent : Double
  duration_ms : Int64
  /// Where the span ends relative to the window: `true` when that edge is the
  /// reader's clock rather than a recorded end.
  open_right_edge : Bool
}

///|
/// Narrowest bar worth drawing, in percent. A 3 ms tool call in a 20-minute run
/// would otherwise be sub-pixel and read as "nothing happened here".
const MinBarPercent : Double = 0.35

///|
/// Keep a percentage inside the drawable range.
fn clamp_percent(value : Double) -> Double {
  if value.is_nan() {
    0.0
  } else if value < 0.0 {
    0.0
  } else if value > 100.0 {
    100.0
  } else {
    value
  }
}

///|
/// Lay one span out on the plain wall-clock window `[t0, t_end]`, ignoring any
/// idle time. Kept for callers that want the raw axis; the viewer uses
/// `layout_trajectory`, which collapses idle by default.
pub fn layout_span(
  span : TrajectorySpan,
  t0_ms : Int64,
  t_end_ms : Int64,
  now_ms : Int64,
) -> WaterfallRow {
  let axis = time_axis([span], t0_ms, t_end_ms, now_ms, compress=false)
  layout_span_on(axis, span, now_ms)
}

///|
/// The horizontal axis a waterfall is drawn on.
///
/// A run can be paused for days — a session resumed a week later — while the
/// work it holds spans a couple of hours. Drawn against the raw wall clock,
/// every bar would be a hairline at one end of an empty frame. So the axis is
/// the stretches where something was actually happening, with one narrow slot
/// per idle stretch between them: the shape of the work fills the frame, and a
/// gap still reads as a gap.
///
/// `gap_ms` is how much drawn room one collapsed idle stretch gets, in the same
/// milliseconds the segments are measured in. `0` means nothing was collapsed
/// and the axis is plain wall-clock time.
pub(all) struct TimeAxis {
  /// Ascending, non-overlapping `(start, end)` stretches drawn at real scale.
  segments : Array[(Int64, Int64)]
  /// The idle stretches folded away, in wall-clock milliseconds. A renderer
  /// prints how long each one was; `gap_ms` says how wide the sliver is.
  gaps : Array[(Int64, Int64)]
  gap_ms : Int64
  /// The axis length in those units.
  length_ms : Int64
  /// How many idle stretches were collapsed. `0` on a plain axis.
  idle_count : Int32
}

///|
/// How much of the frame all the collapsed idle may take. Twenty percent keeps
/// a run with many short gaps from turning into a ladder of spacers.
const MaxIdleShare : Double = 0.2

///|
/// Build the axis for a set of spans.
///
/// `compress` folds every idle stretch between two pieces of work into
/// `gap_ms`; without it the axis is the plain window `[t0, t_end]`, which is
/// what a reader who wants the true idle time to be visible asks for.
pub fn time_axis(
  spans : Array[TrajectorySpan],
  t0_ms : Int64,
  t_end_ms : Int64,
  now_ms : Int64,
  compress~ : Bool,
) -> TimeAxis {
  let window_end = if t_end_ms > now_ms { t_end_ms } else { now_ms }
  if !compress {
    let end = if window_end > t0_ms { window_end } else { t0_ms + 1L }
    return {
      segments: [(t0_ms, end)],
      gaps: [],
      gap_ms: 0L,
      length_ms: end - t0_ms,
      idle_count: 0,
    }
  }
  // Only work whose own duration means something draws the axis. A `Run` and a
  // `Turn` are envelopes: they are open from the first step to the last, so
  // including them would make every gap look like activity and nothing would
  // ever collapse. Their bars still span the gaps afterwards.
  let intervals : Array[(Int64, Int64)] = []
  for span in spans {
    if span.kind is Run || span.kind is Turn {
      continue
    }
    let end = match span.ended_at_ms {
      Some(end) => end
      None => now_ms
    }
    let end = if end < span.started_at_ms { span.started_at_ms } else { end }
    intervals.push((span.started_at_ms, end))
  }
  if intervals.is_empty() {
    // Nothing but envelopes: nothing to fold, so the plain window is the axis.
    let end = if window_end > t0_ms { window_end } else { t0_ms + 1L }
    return {
      segments: [(t0_ms, end)],
      gaps: [],
      gap_ms: 0L,
      length_ms: end - t0_ms,
      idle_count: 0,
    }
  }
  intervals.sort_by((a, b) => a.0.compare(b.0))
  let merged : Array[(Int64, Int64)] = []
  for interval in intervals {
    let join = match merged.last() {
      Some(last) => interval.0 <= last.1
      None => false
    }
    if join {
      let last = merged.unsafe_get(merged.length() - 1)
      if interval.1 > last.1 {
        merged[merged.length() - 1] = (last.0, interval.1)
      }
    } else {
      merged.push(interval)
    }
  }
  let mut active = 0L
  for segment in merged {
    active = active + (segment.1 - segment.0)
  }
  let idle_count = merged.length() - 1
  let gap_ms = if idle_count == 0 || active <= 0L {
    0L
  } else {
    // One gap is a sliver of the active time, and all of them together are
    // capped so a run of a thousand stops still shows its work.
    let per_gap = active / 40L
    let budget = (active.to_double() * MaxIdleShare / idle_count.to_double()).to_int64()
    if per_gap < budget {
      per_gap
    } else {
      budget
    }
  }
  // The real stretches folded away, so a ruler can say how long each was.
  let gaps : Array[(Int64, Int64)] = []
  for i in 1..<merged.length() {
    let previous_end = merged[i - 1].1
    let next_start = merged[i].0
    if next_start > previous_end {
      gaps.push((previous_end, next_start))
    }
  }
  let length_ms = active + gap_ms * idle_count.to_int64()
  {
    segments: merged,
    gaps,
    gap_ms,
    length_ms: if length_ms > 0L {
      length_ms
    } else {
      1L
    },
    idle_count,
  }
}

///|
/// Where an instant sits on the axis, in axis milliseconds.
///
/// An instant inside a collapsed idle stretch lands on the near edge of the
/// next segment: nothing is drawn there, and a bar that spans it keeps its two
/// ends in the right order.
fn axis_position(axis : TimeAxis, ms : Int64) -> Int64 {
  let origin = match axis.segments {
    [(start, _), ..] => start
    [] => 0L
  }
  // A plain axis — one segment, nothing folded — is the wall clock shifted to
  // its own origin; a folded one is accumulated through the segments below,
  // even when a trace too short to spend its idle budget leaves every gap at
  // zero width.
  if axis.idle_count == 0 {
    let offset = ms - origin
    if offset < 0L {
      return 0L
    }
    return offset
  }
  let mut drawn = 0L
  for segment in axis.segments {
    if ms <= segment.0 {
      return drawn
    }
    // An instant exactly on a segment's end belongs to that segment, not to
    // the gap after it: otherwise the last bar before an idle stretch would
    // grow by the whole collapsed gap.
    if ms <= segment.1 {
      return drawn + (ms - segment.0)
    }
    drawn = drawn + (segment.1 - segment.0) + axis.gap_ms
  }
  // Past the last segment: sit on the end of the axis rather than beyond it.
  axis.length_ms
}

///|
/// Lay one span out on an axis.
///
/// Both edges go through the same mapping, so a bar that spans a collapsed gap
/// stays one bar; the gap only makes it thinner than its wall-clock duration
/// suggests, and the duration printed beside it is the real one.
pub fn layout_span_on(
  axis : TimeAxis,
  span : TrajectorySpan,
  now_ms : Int64,
) -> WaterfallRow {
  let effective_end = match span.ended_at_ms {
    Some(end) => end
    None => now_ms
  }
  let start = axis_position(axis, span.started_at_ms)
  let end = axis_position(axis, effective_end)
  let end = if end < start { start } else { end }
  let length = axis.length_ms.to_double()
  let left = start.to_double() / length * 100.0
  let raw_width = (end - start).to_double() / length * 100.0
  {
    span,
    left_percent: clamp_percent(left),
    width_percent: clamp_percent(
      if raw_width < MinBarPercent {
        MinBarPercent
      } else {
        raw_width
      },
    ),
    duration_ms: span.duration_ms(now_ms),
    open_right_edge: span.ended_at_ms is None,
  }
}

///|
/// Lay out every span of a trace on an already built axis, in tree pre-order.
pub fn layout_trajectory_on(
  axis : TimeAxis,
  trajectory : Trajectory,
  now_ms : Int64,
) -> Array[WaterfallRow] {
  [
    for span in trajectory.spans => layout_span_on(axis, span, now_ms)
  ]
}

///|
/// Lay out every span of a trace, in the order they arrived (which is tree
/// pre-order, so rows can be rendered top to bottom).
pub fn layout_trajectory(
  trajectory : Trajectory,
  now_ms : Int64,
  compress~ : Bool = true,
) -> Array[WaterfallRow] {
  let axis = time_axis(
    trajectory.spans,
    trajectory.t0_ms,
    trajectory.t_end_ms,
    now_ms,
    compress~,
  )
  layout_trajectory_on(axis, trajectory, now_ms)
}

///|
/// The axis a trace is drawn on, for a renderer that wants to show the scale
/// itself: where work sits, and how long each folded idle stretch really was.
pub fn axis_of(
  trajectory : Trajectory,
  now_ms : Int64,
  compress~ : Bool = true,
) -> TimeAxis {
  time_axis(
    trajectory.spans,
    trajectory.t0_ms,
    trajectory.t_end_ms,
    now_ms,
    compress~,
  )
}

///|
/// One column of the activity strip: how many calls of each kind *started* in
/// this slice of the axis, and how many steps in it failed.
///
/// The strip is drawn on the same axis as the rows, so a spike sits directly
/// above the steps that caused it, and a folded idle stretch collapses the same
/// way it does in the waterfall.
pub(all) struct ActivityBucket {
  llm : Int32
  tool : Int32
  failed : Int32
}

///|
/// Calls per slice of an already built axis.
pub fn activity_on(
  axis : TimeAxis,
  trajectory : Trajectory,
  buckets~ : Int32 = 60,
) -> Array[ActivityBucket] {
  let count = if buckets > 0 { buckets } else { 1 }
  let out : Array[ActivityBucket] = []
  for _ in 0..<count {
    out.push({ llm: 0, tool: 0, failed: 0, })
  }
  let length = if axis.length_ms > 0L { axis.length_ms } else { 1L }
  for span in trajectory.spans {
    if span.kind is Run || span.kind is Turn {
      continue
    }
    let position = axis_position(axis, span.started_at_ms)
    let raw = (position * count.to_int64() / length).to_int()
    let index = if raw < 0 { 0 } else if raw >= count { count - 1 } else { raw }
    let bucket = out[index]
    out[index] = {
      llm: if span.kind is LlmCall {
        bucket.llm + 1
      } else {
        bucket.llm
      },
      tool: if span.kind is LlmCall {
        bucket.tool
      } else {
        bucket.tool + 1
      },
      failed: if span.status is Failed {
        bucket.failed + 1
      } else {
        bucket.failed
      },
    }
  }
  out
}

///|
/// Calls per slice of the axis.
///
/// Envelopes (`Run`, `Turn`) are not calls, so they never contribute; a failed
/// step counts in `failed` whatever kind it is, which is what makes the red
/// marks line up with the coloured bars below.
pub fn activity_of(
  trajectory : Trajectory,
  now_ms : Int64,
  buckets~ : Int32 = 60,
  compress~ : Bool = true,
) -> Array[ActivityBucket] {
  let axis = time_axis(
    trajectory.spans,
    trajectory.t0_ms,
    trajectory.t_end_ms,
    now_ms,
    compress~,
  )
  activity_on(axis, trajectory, buckets~)
}

///|
/// One mark on a run's time scale: the wall-clock boundary it names and where
/// that boundary lands on the drawn axis.
#derive(Eq)
pub(all) struct AxisTick {
  at_ms : Int64
  axis_ms : Int64
  /// True when the boundary is midnight in the target timezone, so a reader
  /// gets a date rather than a clock time.
  is_day : Bool
}

///|
/// The span between time-scale marks for a run this long.
///
/// A run of seconds gets quarter-minute marks and a run of weeks one per week,
/// so the scale never hands a reader a pile of labels at the same pixel.
pub fn tick_step_ms(span_ms : Int64) -> Int64 {
  if span_ms <= 120_000L {
    15_000L
  } else if span_ms <= 1_200_000L {
    60_000L
  } else if span_ms <= 7_200_000L {
    900_000L
  } else if span_ms <= 43_200_000L {
    3_600_000L
  } else if span_ms <= 259_200_000L {
    21_600_000L
  } else if span_ms <= 1_209_600_000L {
    86_400_000L
  } else {
    604_800_000L
  }
}

///|
fn floor_mod(a : Int64, b : Int64) -> Int64 {
  let rem = a % b
  if rem < 0L {
    rem + b
  } else {
    rem
  }
}

///|
/// The boundaries a run's time scale labels, already placed on the axis.
///
/// Marks sit on round clock times, aligned to the step in the caller's
/// timezone (`tz_offset_ms`, defaulting to UTC), plus the moment each stretch
/// of work began: a night folded away leaves no round mark that survives, and
/// the reader still needs the clock there. A folded axis maps a whole idle
/// stretch onto one narrow slot, so a boundary inside a gap would pile onto
/// its neighbour; those are skipped, as is any mark that lands on the same axis
/// position as the one before it.
pub fn axis_ticks(
  axis : TimeAxis,
  t0_ms : Int64,
  t_end_ms : Int64,
  tz_offset_ms~ : Int64 = 0L,
) -> Array[AxisTick] {
  let step = tick_step_ms(if t_end_ms > t0_ms { t_end_ms - t0_ms } else { 0L })
  let marks : Array[Int64] = []
  let local_t0 = t0_ms + tz_offset_ms
  let mut at = local_t0 - floor_mod(local_t0, step) + step - tz_offset_ms
  while at <= t_end_ms {
    if !in_folded_gap(axis, at) {
      marks.push(at)
    }
    at = at + step
  }
  for segment in axis.segments {
    marks.push(segment.0)
  }
  marks.sort()
  let ticks : Array[AxisTick] = []
  let mut last = -1L
  for mark in marks {
    let position = axis_position(axis, mark)
    if position > last {
      ticks.push({
        at_ms: mark,
        axis_ms: position,
        is_day: floor_mod(mark + tz_offset_ms, 86_400_000L) == 0L,
      })
      last = position
    }
  }
  ticks
}

///|
/// Whether an instant was folded away on this axis: strictly inside an idle
/// stretch the axis compressed, so nothing is drawn there.
fn in_folded_gap(axis : TimeAxis, ms : Int64) -> Bool {
  for gap in axis.gaps {
    if ms > gap.0 && ms < gap.1 {
      return true
    }
  }
  false
}
