// The waterfall's geometry: where a bar sits on the axis and how wide it is.
// Pure arithmetic over spans, so it is tested without a browser.

///|
/// A span on a fixed interval, for the axis tests.
fn axis_span(
  id : String,
  start : Int64,
  end : Int64,
) -> @trajectory.TrajectorySpan {
  {
    id,
    parent_id: None,
    session_id: "run",
    title: "main",
    depth: 0,
    kind: ToolExec,
    status: Succeeded,
    label: id,
    started_at_ms: start,
    ended_at_ms: Some(end),
    job_id: (None : String?),
    job_ids: [],
    sequence: (None : Int32?),
    tag: None,
    metadata: (Map([]) : Map[String, @json.Json]),
  }
}

///|
test "waterfall layout places bars by time and keeps short work visible" {
  let span : @trajectory.TrajectorySpan = {
    id: "s",
    parent_id: None,
    session_id: "run",
    title: "main",
    depth: 0,
    kind: ToolExec,
    status: Succeeded,
    label: "tool",
    started_at_ms: 250L,
    ended_at_ms: Some(750L),
    job_id: None,
    job_ids: [],
    sequence: None,
    tag: None,
    metadata: Map([]),
  }
  let row = @trajectory.layout_span(span, 0L, 1_000L, 1_000L)
  assert_eq(row.left_percent, 25.0)
  assert_eq(row.width_percent, 50.0)
  assert_eq(row.duration_ms, 500L)
  assert_false(row.open_right_edge)
  // A 1 ms call in a 1-minute window still gets a drawable minimum width.
  let tiny : @trajectory.TrajectorySpan = {
    ..span,
    started_at_ms: 30_000L,
    ended_at_ms: Some(30_001L),
  }
  let tiny_row = @trajectory.layout_span(tiny, 0L, 60_000L, 60_000L)
  assert_true(tiny_row.width_percent >= 0.35)
}

///|
test "a running span grows to the reader's clock" {
  let span : @trajectory.TrajectorySpan = {
    id: "s",
    parent_id: None,
    session_id: "run",
    title: "main",
    depth: 0,
    kind: LlmCall,
    status: Running,
    label: "model call",
    started_at_ms: 200L,
    ended_at_ms: None,
    job_id: None,
    job_ids: [],
    sequence: None,
    tag: None,
    metadata: Map([]),
  }
  let early = @trajectory.layout_span(span, 0L, 200L, 300L)
  let later = @trajectory.layout_span(span, 0L, 200L, 600L)
  assert_true(early.open_right_edge)
  assert_true(later.width_percent > early.width_percent)
}

///|
test "an idle gap between work collapses instead of eating the frame" {
  // Two minutes of work, then a night off, then one more minute.
  let spans : Array[@trajectory.TrajectorySpan] = [
    axis_span("a", 0L, 120_000L),
    axis_span("b", 86_520_000L, 86_580_000L),
  ]
  let axis = @trajectory.time_axis(
    spans,
    0L,
    86_580_000L,
    86_580_000L,
    compress=true,
  )
  assert_eq(axis.idle_count, 1)
  // Both pieces of work keep real scale; the night is a sliver.
  assert_true(axis.length_ms < 200_000L)
  let first = @trajectory.layout_span_on(axis, spans[0], 86_580_000L)
  let second = @trajectory.layout_span_on(axis, spans[1], 86_580_000L)
  assert_true(first.width_percent > 40.0)
  assert_true(second.width_percent > 10.0)
  assert_true(second.left_percent > first.left_percent + first.width_percent)
}

///|
test "the same run at true scale is dominated by the idle night" {
  let spans : Array[@trajectory.TrajectorySpan] = [
    axis_span("a", 0L, 120_000L),
    axis_span("b", 86_520_000L, 86_580_000L),
  ]
  let axis = @trajectory.time_axis(
    spans,
    0L,
    86_580_000L,
    86_580_000L,
    compress=false,
  )
  assert_eq(axis.idle_count, 0)
  let first = @trajectory.layout_span_on(axis, spans[0], 86_580_000L)
  // 2 minutes out of 24 hours: a hairline, which is the point of the toggle.
  assert_true(first.width_percent < 1.0)
}

///|
test "overlapping work shares one stretch and no idle slot" {
  let spans : Array[@trajectory.TrajectorySpan] = [
    axis_span("a", 0L, 1_000L),
    axis_span("b", 500L, 2_000L),
    axis_span("c", 1_500L, 3_000L),
  ]
  let axis = @trajectory.time_axis(spans, 0L, 3_000L, 3_000L, compress=true)
  assert_eq(axis.idle_count, 0)
  assert_eq(axis.length_ms, 3_000L)
  let row = @trajectory.layout_span_on(axis, spans[1], 3_000L)
  assert_true((row.left_percent - 100.0 * 500.0 / 3_000.0).abs() < 1.0e-9)
}

///|
test "many short gaps stay a minority of the frame" {
  // A hundred one-second calls with a minute between them: the gaps must not
  // swallow the work.
  let spans : Array[@trajectory.TrajectorySpan] = [
    for i in 0..<100 => {
      let start = i.to_int64() * 61_000L
      axis_span("s\{i}", start, start + 1_000L)
    }
  ]
  let end = 100L * 61_000L
  let axis = @trajectory.time_axis(spans, 0L, end, end, compress=true)
  assert_eq(axis.idle_count, 99)
  let mut active = 0L
  for segment in axis.segments {
    active = active + (segment.1 - segment.0)
  }
  assert_true(axis.length_ms.to_double() <= active.to_double() * 1.25)
}

///|
test "a run envelope does not count as activity on the axis" {
  // The run span covers the whole window; the only work is two short calls a
  // day apart. Folding must still see the day as idle.
  let spans : Array[@trajectory.TrajectorySpan] = [
    { ..axis_span("run", 0L, 86_400_000L), kind: Run, depth: 0, },
    { ..axis_span("a", 0L, 1_000L), kind: ToolExec, },
    { ..axis_span("b", 86_399_000L, 86_400_000L), kind: ToolExec, },
  ]
  let axis = @trajectory.time_axis(
    spans,
    0L,
    86_400_000L,
    86_400_000L,
    compress=true,
  )
  assert_eq(axis.idle_count, 1)
  assert_true(axis.length_ms < 10_000L)
  // The run's own bar still stretches across the folded gap.
  let run_row = @trajectory.layout_span_on(axis, spans[0], 86_400_000L)
  assert_true(run_row.width_percent > 95.0)
}

///|
test "a folded axis whose gaps round to zero still folds" {
  // Two 10 ms calls a second apart: the active time is far below the 40 slots
  // the idle budget is spread over, so every gap is zero width. The mapping
  // must still be the folded one, or the second bar lands past the axis while
  // the ruler draws the segments correctly.
  let spans : Array[@trajectory.TrajectorySpan] = [
    axis_span("a", 0L, 10L),
    axis_span("b", 1_000L, 1_010L),
  ]
  let axis = @trajectory.time_axis(spans, 0L, 1_010L, 1_010L, compress=true)
  assert_eq(axis.idle_count, 1)
  assert_eq(axis.gap_ms, 0L)
  let second = @trajectory.layout_span_on(axis, spans[1], 1_010L)
  // Folded: the second call starts where the first ended, i.e. halfway.
  assert_true((second.left_percent - 50.0).abs() < 1.0e-9)
}

///|
test "the time scale picks a step a reader can read" {
  let minute = 60_000L
  let day = 86_400_000L
  assert_eq(@trajectory.tick_step_ms(minute), 15_000L)
  assert_eq(@trajectory.tick_step_ms(10 * minute), minute)
  assert_eq(@trajectory.tick_step_ms(3_600_000L), 900_000L)
  assert_eq(@trajectory.tick_step_ms(21_600_000L), 3_600_000L)
  assert_eq(@trajectory.tick_step_ms(day), 21_600_000L)
  assert_eq(@trajectory.tick_step_ms(7 * day), day)
  assert_eq(@trajectory.tick_step_ms(30 * day), 604_800_000L)
}

///|
test "the time scale marks round clock times and dates" {
  let hour = 3_600_000L
  let spans : Array[@trajectory.TrajectorySpan] = [
    axis_span("a", 21L * hour, 26L * hour),
  ]
  let axis = @trajectory.time_axis(
    spans,
    21L * hour,
    26L * hour,
    26L * hour,
    compress=false,
  )
  let ticks = @trajectory.axis_ticks(axis, 21L * hour, 26L * hour)
  // The origin plus one mark an hour for the four hours after it.
  assert_eq(ticks.length(), 6)
  assert_eq(ticks[0].at_ms, 21L * hour)
  assert_eq(ticks[1].at_ms, 22L * hour)
  assert_false(ticks[1].is_day)
  // Midnight is the one a reader navigates by.
  assert_eq(ticks[3].at_ms, 86_400_000L)
  assert_true(ticks[3].is_day)
  for index in 1..<ticks.length() {
    assert_true(ticks[index].axis_ms > ticks[index - 1].axis_ms)
  }
}

///|
test "a folded night keeps the clock where work resumed" {
  // Two minutes of work, a night off, one more minute. Every round mark falls
  // inside the night and would pile onto one slot, so the segment starts carry
  // the clock instead.
  let spans : Array[@trajectory.TrajectorySpan] = [
    axis_span("a", 0L, 120_000L),
    axis_span("b", 86_520_000L, 86_580_000L),
  ]
  let axis = @trajectory.time_axis(
    spans,
    0L,
    86_580_000L,
    86_580_000L,
    compress=true,
  )
  let ticks = @trajectory.axis_ticks(axis, 0L, 86_580_000L)
  assert_eq(ticks.length(), 2)
  assert_eq(ticks[0].at_ms, 0L)
  assert_true(ticks[0].is_day)
  assert_eq(ticks[1].at_ms, 86_520_000L)
  assert_true(ticks[1].axis_ms > ticks[0].axis_ms)
}

///|
test "axis_ticks aligns day boundaries to the caller's timezone offset" {
  let hour = 3_600_000L
  let utc_plus_8 = 8L * hour
  // 15:00Z..17:00Z crosses local midnight (16:00Z = 00:00+08:00).
  let start = 15L * hour
  let end = 17L * hour
  let axis = @trajectory.time_axis(
    [axis_span("run", start, end)],
    start,
    end,
    end,
    compress=false,
  )
  let ticks = @trajectory.axis_ticks(axis, start, end, tz_offset_ms=utc_plus_8)
  let midnight = ticks.iter().find_first(t => t.at_ms == 16L * hour)
  guard midnight is Some(tick) else { fail("missing 16:00Z local midnight") }
  assert_true(tick.is_day)
}
