// The trajectory page: one run's whole timeline — every turn of every session
// it spawned, aligned to one clock — drawn as a waterfall.
//
// Everything here is presentation over `@trajectory`: the aggregation (which
// span hangs under which, what is still open) is decided server-side and
// tested headlessly there. This file only answers "how wide is that bar".

///|
/// How many spans of the run failed, which is what the filter's label counts.
fn count_failures(trace : @trajectory.Trajectory) -> Int32 {
  let mut count = 0
  for span in trace.spans {
    if span.status is Failed {
      count += 1
    }
  }
  count
}

///|
/// The rows a "failures only" reader keeps: every failed span, plus the rows
/// that place it, so a failure never hangs off a hidden parent.
///
/// The ancestor walk stops at a row already kept, which keeps the work linear
/// in the tree instead of the tree times its depth.
fn failure_rows(
  all : Array[@trajectory.WaterfallRow],
  visible : Array[@trajectory.WaterfallRow],
) -> Array[@trajectory.WaterfallRow] {
  let parent_of : Map[String, String] = Map([])
  for row in all {
    if row.span.parent_id is Some(parent) {
      parent_of[row.span.id] = parent
    }
  }
  let keep : Map[String, Bool] = Map([])
  for row in all {
    if !(row.span.status is Failed) {
      continue
    }
    keep[row.span.id] = true
    let mut current = row.span.parent_id
    while current is Some(id) {
      if keep.get(id) is Some(_) {
        break
      }
      keep[id] = true
      current = parent_of.get(id)
    }
  }
  visible.filter(row => keep.get(row.span.id) is Some(_))
}

///|
/// Find the span to highlight for `#t=<root>&job=<id>[&start=<ms>]`, preferring
/// the job's own `BackgroundJob` span closest to `start_hint` and falling back
/// to a `JobWait` or start span naming it.
fn find_job_focus_span(
  trace : @trajectory.Trajectory,
  job_id : String,
  start_hint? : Int64,
) -> @trajectory.TrajectorySpan? {
  fn has_job(span : @trajectory.TrajectorySpan) -> Bool {
    span.job_id == Some(job_id) || span.job_ids.contains(job_id)
  }

  fn pick_best(
    candidates : Array[@trajectory.TrajectorySpan],
  ) -> @trajectory.TrajectorySpan? {
    match start_hint {
      None => candidates.get(0)
      Some(target) => {
        let mut best : @trajectory.TrajectorySpan? = None
        let mut best_dist = 0L
        for span in candidates {
          let dist = (span.started_at_ms - target).abs()
          if best is None || dist < best_dist {
            best = Some(span)
            best_dist = dist
          }
        }
        best
      }
    }
  }

  let bg : Array[@trajectory.TrajectorySpan] = []
  let others : Array[@trajectory.TrajectorySpan] = []
  for span in trace.spans {
    if has_job(span) {
      if span.kind is BackgroundJob {
        bg.push(span)
      } else {
        others.push(span)
      }
    }
  }
  match pick_best(bg) {
    Some(span) => Some(span)
    None => pick_best(others)
  }
}

///|
/// Unfold every collapsed ancestor of `target_id` so deep-linked rows are visible.
fn unfold_span_ancestors(
  trace : @trajectory.Trajectory,
  collapsed : Array[String],
  target_id : String,
) -> Array[String] {
  if collapsed.is_empty() {
    return collapsed
  }
  let parent_of : Map[String, String] = Map([])
  for span in trace.spans {
    if span.parent_id is Some(parent) {
      parent_of[span.id] = parent
    }
  }
  let reveal : Map[String, Bool] = Map([])
  let mut current = parent_of.get(target_id)
  while current is Some(id) {
    if reveal.get(id) is Some(_) {
      break
    }
    reveal[id] = true
    current = parent_of.get(id)
  }
  collapsed.filter(id => reveal.get(id) is None)
}

///|
/// Drop any collapsed ancestor of a failed span so "Failures only" or
/// "jump to first" never lands on a hidden subtree.
fn unfold_failed_ancestors(
  trace : @trajectory.Trajectory,
  collapsed : Array[String],
) -> Array[String] {
  if collapsed.is_empty() {
    return collapsed
  }
  let parent_of : Map[String, String] = Map([])
  for span in trace.spans {
    if span.parent_id is Some(parent) {
      parent_of[span.id] = parent
    }
  }
  let reveal : Map[String, Bool] = Map([])
  for span in trace.spans {
    if !(span.status is Failed) {
      continue
    }
    let mut current = span.parent_id
    while current is Some(id) {
      if reveal.get(id) is Some(_) {
        break
      }
      reveal[id] = true
      current = parent_of.get(id)
    }
  }
  collapsed.filter(id => reveal.get(id) is None)
}

///|
const WaterfallRowHeightPx : Int32 = 32

///|
const WaterfallVirtualThreshold : Int32 = 120

///|
const WaterfallVirtualOverscan : Int32 = 16

///|
const AutoCollapseSpanThreshold : Int32 = 200

///|
/// Fold early completed turns in large runs on initial load so the viewer opens
/// on the latest turn and any failed or actively running branches.
fn auto_collapsed_turns(trace : @trajectory.Trajectory) -> Array[String] {
  if trace.spans.length() <= AutoCollapseSpanThreshold {
    return []
  }
  let turns : Array[String] = []
  let parent_of : Map[String, String] = Map([])
  for span in trace.spans {
    if span.parent_id is Some(parent) {
      parent_of[span.id] = parent
    }
    if span.kind is Turn {
      turns.push(span.id)
    }
  }
  if turns.length() <= 1 {
    return []
  }
  let keep_open : Map[String, Bool] = Map([])
  keep_open[turns[turns.length() - 1]] = true
  for span in trace.spans {
    if !(span.status is (Failed | Running)) {
      continue
    }
    if span.kind is Turn {
      keep_open[span.id] = true
    }
    let mut current = span.parent_id
    while current is Some(id) {
      if keep_open.get(id) is Some(_) {
        break
      }
      keep_open[id] = true
      current = parent_of.get(id)
    }
  }
  turns.filter(id => keep_open.get(id) is None)
}

///|
fn virtual_window(
  total : Int32,
  scroll_top : Int32,
  viewport_h : Int32,
) -> (Int32, Int32) {
  if total <= WaterfallVirtualThreshold {
    return (0, total)
  }
  let height = if viewport_h > 0 { viewport_h } else { 900 }
  let max_top = total * WaterfallRowHeightPx - height
  let top = if scroll_top <= 0 || max_top <= 0 {
    0
  } else if scroll_top > max_top {
    max_top
  } else {
    scroll_top
  }
  let raw_start = top / WaterfallRowHeightPx - WaterfallVirtualOverscan
  let start = if raw_start > 0 { raw_start } else { 0 }
  let raw_end = (top + height) / WaterfallRowHeightPx +
    1 +
    WaterfallVirtualOverscan
  let end = if raw_end < total { raw_end } else { total }
  (start, end)
}

///|
fn visible_trajectory_rows(
  trace : @trajectory.Trajectory,
  collapsed : Array[String],
  failed_only : Bool,
) -> Array[@trajectory.WaterfallRow] {
  let now_ms = browser_now_ms()
  let axis = @trajectory.axis_of(trace, now_ms, compress=true)
  let all_rows = @trajectory.layout_trajectory_on(axis, trace, now_ms)
  let rows = visible_rows(all_rows, collapsed)
  if failed_only {
    failure_rows(all_rows, rows)
  } else {
    rows
  }
}

///|
fn find_first_failure_row_index(
  trace : @trajectory.Trajectory,
  collapsed : Array[String],
  failed_only : Bool,
) -> Int32? {
  let rows = visible_trajectory_rows(trace, collapsed, failed_only)
  for i in 0..<rows.length() {
    if rows[i].span.status is Failed {
      return Some(i)
    }
  }
  None
}

///|
fn find_span_row_index(
  trace : @trajectory.Trajectory,
  collapsed : Array[String],
  failed_only : Bool,
  span_id : String,
) -> Int32? {
  let rows = visible_trajectory_rows(trace, collapsed, failed_only)
  for i in 0..<rows.length() {
    if rows[i].span.id == span_id {
      return Some(i)
    }
  }
  None
}

///|
/// Render the whole trace: header, totals, legend, and the waterfall rows.
fn trajectory_pane(
  emit : @cmd.Emit[Msg],
  model : Model,
  trace : @trajectory.Trajectory,
) -> @html.Html {
  let now_ms = browser_now_ms()
  let wall = if trace.live {
    (now_ms - trace.t0_ms).max(0L)
  } else {
    trace.stats.wall_ms
  }
  // Build the axis once per render so layout, activity histogram, ruler, scale
  // and grid share the exact same coordinates without repeating the sort.
  let axis = @trajectory.axis_of(
    trace,
    now_ms,
    compress=model.trajectory_compact,
  )
  let all_rows = @trajectory.layout_trajectory_on(axis, trace, now_ms)
  let rows = visible_rows(all_rows, model.trajectory_collapsed)
  // A run of thousands of spans needs the cut the log view already offers:
  // keep the failures and the rows that place them.
  let failures = count_failures(trace)
  let rows = if model.trajectory_failed_only {
    failure_rows(all_rows, rows)
  } else {
    rows
  }
  let tz_offset_ms = local_tz_offset_ms(trace.t0_ms.to_double()).to_int64()
  let tz_label = local_tz_label(trace.t0_ms.to_double())
  let ticks = @trajectory.axis_ticks(
    axis,
    trace.t0_ms,
    trace.t_end_ms,
    tz_offset_ms~,
  )
  let tick_step = @trajectory.tick_step_ms(wall_span_of(trace))
  // A lane's role belongs at its head: which session owns the row, and whether
  // it is the run's own session or one the run spawned.
  let lane_roles : Map[String, LaneBadge] = Map([])
  for session in trace.sessions {
    lane_roles[session.session_id] = {
      role: match session.parent_session_id {
        Some(_) => Sub
        None => Main
      },
      title: match session.parent_session_id {
        Some(parent) => "sub-agent \{session.session_id}, spawned by \{parent}"
        None => "main session \{session.session_id}"
      },
    }
  }
  let lane_seen : Map[String, Bool] = Map([])
  // A parent's own children, so a row can tell in O(1) whether it is
  // collapsible and draw what it contains as ticks.
  let children_of = span_children_map(all_rows)
  // Rows are built as an array so the grid overlay can be appended once after
  // them, instead of being repeated in every row.
  let body_rows : Array[@html.Html] = []
  // Job keys whose log this pane has already placed: the same job can appear
  // on more than one row, and its log belongs under one of them.
  let log_drawn : Array[String] = []
  let total_rows = rows.length()
  let (v_start, v_end) = virtual_window(
    total_rows,
    model.trajectory_scroll_top,
    model.trajectory_viewport_h,
  )
  for i in 0..<v_start {
    let span = rows[i].span
    lane_seen[span.session_id] = true
  }
  if v_start > 0 {
    body_rows.push(
      @html.div(
        class="waterfall-spacer",
        style=["height: \{v_start * WaterfallRowHeightPx}px"],
      ) <| "",
    )
  }
  for i in v_start..<v_end {
    let row = rows[i]
    let first_of_lane = lane_seen.get(row.span.session_id) is None
    lane_seen[row.span.session_id] = true
    // Offer `.out` toggles for every background job referenced by this span.
    let job_toggles : Array[JobToggle] = [
      for key in span_job_keys(row.span) if job_log_available(model, key) => {
        { key, open: model.trajectory_job_open.contains(key), }
      }
    ]
    body_rows.push(
      waterfall_row(
        emit,
        trace,
        row,
        collapsible=children_of.get(row.span.id) is Some(_),
        collapsed=model.trajectory_collapsed.contains(row.span.id),
        children=children_of.get(row.span.id).unwrap_or([]),
        badge?=if first_of_lane {
          lane_roles.get(row.span.session_id)
        } else {
          None
        },
        focused=model.trajectory_focus_span == Some(row.span.id),
        even=i % 2 == 1,
        job_toggles~,
      ),
    )
    // A job's log opens under the first row that named it, indented to that
    // row's label so the two read as one block. A run often names the same job
    // twice (its own span, and the wait that blocked on it); showing the log
    // under both would print it twice.
    for toggle in job_toggles {
      if toggle.open && !log_drawn.contains(toggle.key) {
        log_drawn.push(toggle.key)
        body_rows.push(job_log_block(emit, model, row.span, toggle.key))
      }
    }
  }
  if v_end < total_rows {
    body_rows.push(
      @html.div(
        class="waterfall-spacer",
        style=["height: \{(total_rows - v_end) * WaterfallRowHeightPx}px"],
      ) <| "",
    )
  }
  @html.div(class="session-view trajectory-view") <| [
    trajectory_header(model, trace),
    if model.standalone && trace.live {
      @html.div(class="snapshot-banner") <| "Static snapshot of a live run · Re-open from Desktop (or use inspect --watch) for newer progress."
    } else {
      @html.nothing
    },
    trajectory_stats(emit, trace, wall),
    trajectory_activity(trace, axis, compact=model.trajectory_compact),
    trajectory_axis_ruler(axis),
    @html.div(class="sticky-toolbar") <| [
      @html.div(class="mode-row") <| [
        @html.div(class="mode-cluster") <| [
          @html.button(
            class="mode-button",
            title="Back to the selected session's log",
            on_click=emit(CloseTrajectory),
          ) <| "Back to log",
          // Default to folded idle gaps; allow switching to linear scale locally.
          @html.button(
            class="mode-button",
            title=if model.trajectory_compact {
              "Show idle time at true scale"
            } else {
              "Collapse the idle stretches between work"
            },
            on_click=emit(ToggleTrajectoryAxis),
          ) <| (if model.trajectory_compact {
            "Idle folded"
          } else {
            "Idle at scale"
          }),
          @html.button(
            class="mode-button",
            title=if model.trajectory_failed_only {
              "Show every step again"
            } else {
              "Keep only the failed steps and the rows that place them"
            },
            on_click=emit(ToggleTrajectoryFailures),
          ) <| (if failures == 0 {
            "Failures · none"
          } else if model.trajectory_failed_only {
            "Failures only · \{failures}"
          } else {
            "Failures · \{failures}"
          }),
        ],
        @html.div(class="trajectory-totals") <| axis_note(
          model.trajectory_compact,
          wall,
        ),
      ],
      trajectory_legend(),
    ],
    if model.trajectory_failed_only && rows.is_empty() {
      @html.div(class="placeholder trajectory-placeholder") <| "no failed steps in this run"
    } else {
      let wf_class = if total_rows > WaterfallVirtualThreshold {
        "waterfall waterfall-virtual"
      } else {
        "waterfall"
      }
      @html.div(class=wf_class) <| [
        trajectory_scale(ticks, axis, tick_step, tz_label),
        @html.div(class="waterfall-body") <| [
          ..body_rows,
          trajectory_grid(ticks, axis),
        ],
      ]
    },
  ]
}

///|
fn trajectory_header(
  model : Model,
  trace : @trajectory.Trajectory,
) -> @html.Html {
  let live_note = if trace.live { " · live" } else { "" }
  let root = match model.trajectory_root {
    Some(root) => root
    None => trace.root_session_id
  }
  @html.header(class="header-strip") <| [
    @html.div(class="header-id") <| "run \{root}",
    @html.div(class="header-meta") <| "\{trace.sessions.length()} session(s) · \{trace.stats.turn_count} turn(s) · \{trace.stats.span_count} span(s)\{live_note}",
  ]
}

///|

///|
/// One colour chip per span kind, so a bar's colour can be read without
/// hovering it.
fn trajectory_legend() -> @html.Html {
  let entries : Array[(String, String)] = [
    ("turn", "turn"),
    ("llm", "model"),
    ("tool", "tool"),
    ("workflow", "mbtx"),
    ("ptc", "ptc"),
    ("job", "job"),
    ("wait", "wait"),
    ("milestone", "milestone"),
  ]
  @html.div(class="waterfall-legend") <| [
    for entry in entries => {
      @html.span(class="waterfall-legend-item") <| [
        @html.span(class="waterfall-swatch kind-\{entry.0}") <| "",
        @html.span(class="waterfall-legend-label") <| entry.1,
      ]
    }
  ]
}

///|
/// One row: the indent, the label, and the bar placed on the shared axis.
fn waterfall_row(
  emit : @cmd.Emit[Msg],
  trace : @trajectory.Trajectory,
  row : @trajectory.WaterfallRow,
  collapsible~ : Bool,
  collapsed~ : Bool,
  children~ : Array[@trajectory.WaterfallRow],
  badge? : LaneBadge,
  focused~ : Bool,
  even~ : Bool,
  job_toggles~ : Array[JobToggle],
) -> @html.Html {
  let span = row.span
  // An envelope shows what it contains as ticks, so the shape of the work
  // reads without expanding a thousand rows.
  let ticks : Array[@html.Html] = [
    for child in children => {
      @html.div(
        class="waterfall-tick kind-\{child.span.kind.tag()} status-\{child.span.status.tag()}",
        style=[
          "left: \{round1(child.left_percent)}%",
          "width: \{round1(child.width_percent)}%",
        ],
      ) <| ""
    }
  ]
  let indent = span.depth * 14
  let on_critical = trace.stats.critical_path.contains(span.id)
  let class_names = [
      "waterfall-row",
      if even {
        "waterfall-row-even"
      } else {
        ""
      },
      "kind-\{span.kind.tag()}",
      "status-\{span.status.tag()}",
      match span.tag {
        Some(tag) => "tag-\{tag.tag()}"
        None => ""
      },
      if on_critical {
        "critical"
      } else {
        ""
      },
      if focused {
        "job-focus"
      } else {
        ""
      },
      if row.open_right_edge {
        "open"
      } else {
        ""
      },
      if collapsed {
        "collapsed"
      } else {
        ""
      },
    ]
    .filter(name => !name.is_empty())
    .join(" ")
  let title = waterfall_title(span, row)
  @html.div(class=class_names, title~) <| [
    @html.div(class="waterfall-label", style=["padding-left: \{indent}px"]) <| [
      match collapsible {
        // A row with children folds its subtree; a leaf keeps the space so
        // labels stay aligned down the column.
        true =>
          @html.button(
            class="waterfall-toggle",
            title=if collapsed {
              "Show what this step did"
            } else {
              "Hide what this step did"
            },
            on_click=emit(ToggleTrajectorySpan(row.span.id)),
          ) <| (if collapsed { "▸" } else { "▾" })
        false => @html.span(class="waterfall-toggle placeholder") <| ""
      },
      match badge {
        Some(badge) =>
          @html.span(
            class="lane-role \{badge.role.class_name()}",
            title=badge.title,
          ) <| badge.role.glyph()
        None => @html.nothing
      },
      @html.span(class="waterfall-dot") <| "",
      @html.span(class="waterfall-name") <| span.label,
      @html.span(class="waterfall-caption") <| waterfall_caption(span),
      // The way into each named job's own output. It sits beside the label
      // rather than behind a hover, because "what did this job print" is the
      // first question a long job or wait row raises.
      ..[
        for toggle in job_toggles => {
          let label = if job_toggles.length() == 1 {
            ".out"
          } else {
            "\{job_id_of_key(toggle.key)}.out"
          }
          @html.button(
            class="job-log-button",
            title=if toggle.open {
              "Hide what \{job_id_of_key(toggle.key)} printed"
            } else {
              "Show what \{job_id_of_key(toggle.key)} printed"
            },
            attrs=@html.Attrs::build().aria_expanded(
              if toggle.open {
                "true"
              } else {
                "false"
              },
            ),
            on_click=emit(ToggleJobLog(toggle.key)),
          ) <| (if toggle.open { "▾ \{label}" } else { "▸ \{label}" })
        }
      ],
    ],
    @html.div(class="waterfall-track") <| [
      @html.div(
        class="waterfall-bar",
        style=[
          "left: \{round1(row.left_percent)}%",
          "width: \{round1(row.width_percent)}%",
        ],
      ) <| "",
      ..ticks,
    ],
    @html.div(class="waterfall-duration") <| [
      @html.span(class="waterfall-ms") <| duration_label(row.duration_ms),
      @html.a(
        class="waterfall-open",
        href=open_href(span),
        title="Open this step in its session's log",
      ) <| "↗",
    ],
    @html.div(class="waterfall-tip") <| tooltip_text(span, row),
  ]
}

///|
/// The right-hand caption of a row: the session it belongs to, plus the job ids
/// when the span is about one or more background jobs.
fn waterfall_caption(span : @trajectory.TrajectorySpan) -> String {
  let job = if !span.job_ids.is_empty() {
    let ids = span.job_ids.join(", ")
    " · \{ids}"
  } else {
    match span.job_id {
      Some(id) => " · \{id}"
      None => ""
    }
  }
  "\{span.title}\{job}"
}

///|
/// The hover text: what the span is, who ran it, and — when the log recorded
/// one — the tool's own one-line summary.
fn waterfall_title(
  span : @trajectory.TrajectorySpan,
  row : @trajectory.WaterfallRow,
) -> String {
  let brief = match span.metadata.get("brief") {
    Some(String(brief)) => " · \{brief}"
    _ => ""
  }
  let prompt = match span.metadata.get("prompt") {
    Some(String(prompt)) => " · \{prompt}"
    _ => ""
  }
  let state = if row.open_right_edge { "running" } else { span.status.tag() }
  "\{span.label} · \{span.title} · \{state} · \{duration_label(row.duration_ms)}\{brief}\{prompt}"
}

///|
/// A human duration: milliseconds, then seconds, then minutes, hours and days,
/// so neither a 3 ms tool call nor a run resumed over a week reads as a raw
/// millisecond count.
fn duration_label(ms : Int64) -> String {
  if ms < 1_000L {
    "\{ms} ms"
  } else if ms < 59_950L {
    let seconds = round1(ms.to_double() / 1_000.0)
    "\{seconds} s"
  } else if ms < 60_000L {
    "1m 0s"
  } else if ms < 3_600_000L {
    let minutes = ms / 60_000L
    "\{minutes}m \{ms % 60_000L / 1_000L}s"
  } else if ms < 86_400_000L {
    let hours = ms / 3_600_000L
    "\{hours}h \{ms % 3_600_000L / 60_000L}m"
  } else {
    let days = ms / 86_400_000L
    "\{days}d \{ms % 86_400_000L / 3_600_000L}h"
  }
}

///|
/// A token count in the unit a reader can hold in mind: `86.2k`, `116.0M`.
/// A run bills hundreds of millions of prompt tokens across its model calls,
/// which as a bare number is unreadable.
fn token_label(tokens : Int64) -> String {
  let value = tokens.to_double()
  if value < 1_000.0 {
    "\{tokens}"
  } else if value < 999_950.0 {
    "\{round1(value / 1_000.0)}k"
  } else {
    "\{round1(value / 1_000_000.0)}M"
  }
}

///|
/// One decimal place, without the trailing `.0`.
fn round1(value : Double) -> String {
  let scaled = (value * 10.0).round()
  let whole = (scaled / 10.0).to_int()
  let fraction = scaled.to_int() % 10
  if fraction == 0 {
    "\{whole}"
  } else {
    "\{whole}.\{fraction}"
  }
}

///|
/// One `/api/trajectory/<id>` answer: the whole document, or the `unchanged`
/// acknowledgement a poll gets when no participating file moved.
priv enum TrajectoryReply {
  Trace(@trajectory.Trajectory, String?)
  Unchanged
}

///|
/// Decode a `/api/trajectory/<id>` body, with the cursor it carries. `None`
/// covers both a network failure and a body this build cannot read; the caller
/// shows `model.status`.
fn parse_trajectory_reply(text : String) -> TrajectoryReply? {
  let json = @json.parse(text) catch { _ => return None }
  if json is { "unchanged": True, .. } {
    return Some(Unchanged)
  }
  let cursor = match json {
    { "cursor": String(token), .. } => Some(token)
    _ => None
  }
  let trace = @trajectory.parse_trajectory(json) catch { _ => return None }
  Some(Trace(trace, cursor))
}

///|
/// Index rows by their parent id once per render so each row checks
/// collapsibility and draws child ticks in O(1).
fn span_children_map(
  rows : Array[@trajectory.WaterfallRow],
) -> Map[String, Array[@trajectory.WaterfallRow]] {
  let children_of : Map[String, Array[@trajectory.WaterfallRow]] = Map([])
  for candidate in rows {
    match candidate.span.parent_id {
      Some(parent) =>
        match children_of.get(parent) {
          Some(bucket) => bucket.push(candidate)
          None => children_of[parent] = [candidate]
        }
      None => ()
    }
  }
  children_of
}

///|
/// The rows a reader can currently see: everything, minus the descendants of a
/// span they folded away.
///
/// Rows arrive in tree pre-order with their depth, so one pass with a stack of
/// the current ancestors answers "is anything above me collapsed?" without
/// walking parent pointers or rebuilding the tree here.
fn visible_rows(
  rows : Array[@trajectory.WaterfallRow],
  collapsed : Array[String],
) -> Array[@trajectory.WaterfallRow] {
  if collapsed.is_empty() {
    return rows
  }
  let ancestors : Array[String] = []
  let visible : Array[@trajectory.WaterfallRow] = []
  for row in rows {
    let depth = row.span.depth
    while ancestors.length() > depth && ancestors.length() > 0 {
      let _ = ancestors.pop()
    }
    let hidden = ancestors.any(id => collapsed.contains(id))
    // A folded row still moves the stack itself: it is on the path for its own
    // children even though they are not drawn.
    ancestors.push(row.span.id)
    if !hidden {
      visible.push(row)
    }
  }
  visible
}

///|
/// The run's headline numbers, as cards: duration, shape, where the time
/// went, and how many steps failed.
fn trajectory_stats(
  emit : @cmd.Emit[Msg],
  trace : @trajectory.Trajectory,
  wall : Int64,
) -> @html.Html {
  let errors = trace.spans.filter(span => span.status is Failed).length()
  let share = (ms : Int64) => {
    if wall <= 0L {
      "—"
    } else {
      "\{round1(ms.to_double() / wall.to_double() * 100.0)}% of wall"
    }
  }
  @html.div(class="trajectory-stats") <| [
    stat_card(
      "duration",
      duration_label(wall),
      "\{clock_label(trace.t0_ms)} → \{clock_label(trace.t_end_ms)}",
    ),
    stat_card(
      "agents · turns",
      "\{trace.stats.session_count} · \{trace.stats.turn_count}",
      "\{trace.stats.span_count} spans",
    ),
    stat_card(
      "model",
      duration_label(trace.stats.llm_ms),
      share(trace.stats.llm_ms),
    ),
    stat_card(
      "tools",
      duration_label(trace.stats.tool_ms),
      share(trace.stats.tool_ms),
    ),
    stat_card(
      "waiting",
      duration_label(waiting_ms(trace.spans)),
      "job_wait inside jobs, merged",
    ),
    stat_card(
      "tokens",
      token_label(trace.stats.prompt_tokens),
      "\{token_label(trace.stats.completion_tokens)} out",
    ),
    error_card(emit, errors),
  ]
}

///|
fn stat_card(label : String, value : String, note : String) -> @html.Html {
  @html.div(class="stat") <| [
    @html.div(class="stat-label") <| label,
    @html.div(class="stat-value") <| value,
    @html.div(class="stat-note") <| note,
  ]
}

///|
/// The failure count, with a jump to the first failed step when there is one.
fn error_card(emit : @cmd.Emit[Msg], errors : Int32) -> @html.Html {
  let body : Array[@html.Html] = [
    @html.div(class="stat-label") <| "errors",
    @html.div(class=if errors > 0 { "stat-value bad" } else { "stat-value" }) <| "\{errors}",
  ]
  if errors > 0 {
    body.push(
      @html.button(class="stat-jump", on_click=emit(JumpToFirstFailure)) <| "jump to first ›",
    )
  } else {
    body.push(@html.div(class="stat-note") <| "none")
  }
  @html.div(class="stat") <| body
}

///|
/// The wall-clock time of an instant in the browser's local timezone, as `HH:MM`.
fn clock_label(ms : Int64) -> String {
  let text = format_unix_ms_local(ms.to_double())
  if text.length() >= 16 {
    text[11:16].to_owned()
  } else {
    text
  }
}

///|
/// What the axis is showing, said beside the toggles so the numbers and the
/// bars cannot read as a contradiction.
fn axis_note(compact : Bool, wall : Int64) -> String {
  let wall_note = "wall \{duration_label(wall)}"
  if compact {
    "\{wall_note} · idle folded"
  } else {
    "\{wall_note} · idle at scale"
  }
}

///|
/// The ruler above the rows: one block per stretch of real work and one narrow
/// slot per folded idle stretch, labelled with how long that stretch was.
fn trajectory_axis_ruler(axis : @trajectory.TimeAxis) -> @html.Html {
  let total = if axis.length_ms > 0L { axis.length_ms.to_double() } else { 1.0 }
  let blocks : Array[@html.Html] = []
  let segments = axis.segments
  let mut cursor = 0L
  for index in 0..<segments.length() {
    let (start, end) = segments[index]
    let seg_ms = end - start
    let left = cursor.to_double() / total * 100.0
    let width = seg_ms.to_double() / total * 100.0
    blocks.push(
      @html.div(
        class="ruler-seg",
        style=["left: \{round1(left)}%", "width: \{round1(width)}%"],
      ) <| [
        if index == 0 {
          @html.span(class="ruler-tick") <| clock_label(start)
        } else {
          @html.nothing
        },
      ],
    )
    cursor = cursor + seg_ms
    if index < axis.gaps.length() {
      let (gap_start, gap_end) = axis.gaps[index]
      let gap_left = cursor.to_double() / total * 100.0
      let gap_width = axis.gap_ms.to_double() / total * 100.0
      let gap_text = duration_label(gap_end - gap_start)
      blocks.push(
        @html.div(
          class="ruler-gap",
          title="idle \{gap_text}",
          style=["left: \{round1(gap_left)}%", "width: \{round1(gap_width)}%"],
        ) <| gap_text,
      )
      cursor = cursor + axis.gap_ms
    }
  }
  @html.div(
    class="waterfall-ruler",
    title="One block per stretch of work; each narrow slot is idle time, labelled with its real length",
  ) <| [
    @html.div(class="ruler-corner") <| "axis",
    @html.div(class="ruler-blocks") <| blocks,
    @html.div(class="ruler-corner") <| "",
  ]
}

///|
/// The hover card under a row: what the step is, how it ended, and what the
/// log recorded about it. Kept as DOM text so it survives without JS.
fn tooltip_text(
  span : @trajectory.TrajectorySpan,
  row : @trajectory.WaterfallRow,
) -> String {
  let state = if row.open_right_edge { "running" } else { span.status.tag() }
  let brief = match span.metadata.get("brief") {
    Some(String(brief)) => "\n\{brief}"
    _ => ""
  }
  let prompt = match span.metadata.get("prompt") {
    Some(String(prompt)) => "\nprompt: \{prompt}"
    _ => ""
  }
  "\{span.label} · \{span.title}\n\{span.kind.tag()} · \{state} · \{duration_label(row.duration_ms)}\{brief}\{prompt}"
}

///|
/// The activity strip: how many calls started in each slice of the axis, with
/// a red mark over any slice that holds a failure.
fn trajectory_activity(
  trace : @trajectory.Trajectory,
  axis : @trajectory.TimeAxis,
  compact~ : Bool,
) -> @html.Html {
  let buckets = @trajectory.activity_on(axis, trace)
  let mut peak = 1
  for bucket in buckets {
    let total = bucket.llm + bucket.tool
    if total > peak {
      peak = total
    }
  }
  let columns : Array[@html.Html] = [
    for bucket in buckets => {
      let total = bucket.llm + bucket.tool
      let height = total.to_double() / peak.to_double() * 100.0
      @html.div(
        class="activity-col",
        title="\{bucket.llm} model · \{bucket.tool} tool · \{bucket.failed} failed",
      ) <| [
        @html.div(class="activity-bar", style=["height: \{round1(height)}%"]) <| [
          @html.div(class="activity-seg llm", style=["flex: \{bucket.llm}"]) <| "",
          @html.div(class="activity-seg tool", style=["flex: \{bucket.tool}"]) <| "",
        ],
        if bucket.failed > 0 {
          @html.div(class="activity-error") <| ""
        } else {
          @html.nothing
        },
      ]
    }
  ]
  @html.div(class="activity-strip") <| [
    @html.div(class="activity-head") <| [
      @html.span(class="activity-title") <| "activity",
      @html.span(class="activity-note") <| (if compact {
        "calls per slice · idle folded"
      } else {
        "calls per slice · idle at scale"
      }),
      @html.span(class="activity-key") <| [
        @html.span(class="waterfall-swatch kind-llm") <| "",
        @html.span(class="activity-key-label") <| "model",
        @html.span(class="waterfall-swatch kind-tool") <| "",
        @html.span(class="activity-key-label") <| "tool",
        @html.span(class="activity-error sample") <| "",
        @html.span(class="activity-key-label") <| "failed",
      ],
    ],
    @html.div(class="activity-row") <| [
      @html.div(class="ruler-corner") <| "",
      @html.div(class="activity-columns") <| columns,
      @html.div(class="ruler-corner") <| "",
    ],
  ]
}

///|
/// The log position a row opens: its session, and the durable event the span
/// was read from. Without a sequence the session alone is still worth opening.
fn open_href(span : @trajectory.TrajectorySpan) -> String {
  match span.sequence {
    Some(sequence) =>
      "#s=\{encode_uri_component(span.session_id)}&seq=\{sequence}"
    None => "#s=\{encode_uri_component(span.session_id)}"
  }
}

///|
/// How long the run spent blocked on background work.
///
/// `wait_ms` and `job_ms` are separate sums, and a `job_wait` happens inside
/// the jobs it waits on: adding them counts the same minutes twice, and can
/// claim more waiting than the run is long. Two jobs that ran at once are one
/// stretch of waiting, so the intervals are merged rather than summed.
fn waiting_ms(spans : Array[@trajectory.TrajectorySpan]) -> Int64 {
  let intervals : Array[(Int64, Int64)] = []
  for span in spans {
    if span.ended_at_ms is Some(end) &&
      (span.kind is BackgroundJob || span.kind is JobWait) &&
      end > span.started_at_ms {
      intervals.push((span.started_at_ms, end))
    }
  }
  intervals.sort_by((a, b) => a.0.compare(b.0))
  let mut total = 0L
  let mut open = false
  let mut open_start = 0L
  let mut open_end = 0L
  for interval in intervals {
    if open && interval.0 <= open_end {
      if interval.1 > open_end {
        open_end = interval.1
      }
    } else {
      if open {
        total = total + (open_end - open_start)
      }
      open_start = interval.0
      open_end = interval.1
      open = true
    }
  }
  if open {
    total = total + (open_end - open_start)
  }
  total
}

///|
/// The window a run covers, which is what its time scale is drawn over.
fn wall_span_of(trace : @trajectory.Trajectory) -> Int64 {
  if trace.t_end_ms > trace.t0_ms {
    trace.t_end_ms - trace.t0_ms
  } else {
    0L
  }
}

///|
/// What a lane is: the run's own session, or an agent the run spawned.
priv enum LaneRole {
  Main
  Sub
}

///|
fn LaneRole::glyph(self : LaneRole) -> String {
  match self {
    Main => "◆"
    Sub => "◇"
  }
}

///|
fn LaneRole::class_name(self : LaneRole) -> String {
  match self {
    Main => "lane-role-main"
    Sub => "lane-role-sub"
  }
}

///|
/// A lane's role, shown once at the head of its rows.
priv struct LaneBadge {
  role : LaneRole
  title : String
}

///|
/// Where one mark sits on the drawn axis, as a percentage of its width.
fn tick_percent(
  tick : @trajectory.AxisTick,
  axis : @trajectory.TimeAxis,
) -> Double {
  let length = if axis.length_ms > 0L {
    axis.length_ms.to_double()
  } else {
    1.0
  }
  tick.axis_ms.to_double() / length * 100.0
}

///|
let month_names : Array[String] = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

///|
/// The text of one time-scale mark: a date at a day boundary, otherwise a clock
/// time, with seconds when the step is below a minute.
fn tick_label(tick : @trajectory.AxisTick, step_ms : Int64) -> String {
  tick_label_from(format_unix_ms_local(tick.at_ms.to_double()), tick, step_ms)
}

///|
/// Pure formatter over a `YYYY-MM-DD HH:MM` timestamp string.
fn tick_label_from(
  stamp : String,
  tick : @trajectory.AxisTick,
  step_ms : Int64,
) -> String {
  if tick.is_day {
    return day_label(stamp)
  }
  if stamp.length() < 16 {
    return stamp
  }
  let clock = stamp[11:16].to_owned()
  if step_ms < 60_000L {
    let seconds = tick.at_ms % 60_000L / 1_000L
    "\{clock}:\{if seconds < 10L { "0" } else { "" }}\{seconds}"
  } else {
    clock
  }
}

///|
/// A dated label like `Nov 1` from a `YYYY-MM-DD HH:MM` stamp.
fn day_label(stamp : String) -> String {
  if stamp.length() < 10 {
    return stamp
  }
  let month = decimal_prefix(stamp[5:7].to_owned()).to_int() - 1
  let day = decimal_prefix(stamp[8:10].to_owned()).to_int()
  if month < 0 || month >= 12 {
    return stamp[:10].to_owned()
  }
  "\{month_names[month]} \{day}"
}

///|
/// The dated scale above the waterfall, column-aligned with the bars.
fn trajectory_scale(
  ticks : Array[@trajectory.AxisTick],
  axis : @trajectory.TimeAxis,
  step_ms : Int64,
  tz_label : String,
) -> @html.Html {
  let labels : Array[@html.Html] = []
  for tick in ticks {
    let percent = tick_percent(tick, axis)
    // A label near the right edge would spill out of the track and be clipped,
    // so it hangs to the left of its line instead.
    let class = match (tick.is_day, percent > 88.0) {
      (true, true) => "scale-label day end"
      (true, false) => "scale-label day"
      (false, true) => "scale-label end"
      (false, false) => "scale-label"
    }
    labels.push(
      @html.span(
        class~,
        style=["left: \{round1(percent)}%"],
        title="\{format_unix_ms_local(tick.at_ms.to_double())} \{tz_label}",
      ) <| tick_label(tick, step_ms),
    )
  }
  @html.div(class="waterfall-scale") <| [
    @html.div(class="scale-corner") <| tz_label,
    @html.div(class="scale-track") <| labels,
    @html.div(class="scale-corner") <| "",
  ]
}

///|
/// The grid the scale casts down the rows: one hairline per mark, so a bar can
/// be read against the clock without leaving its row.
fn trajectory_grid(
  ticks : Array[@trajectory.AxisTick],
  axis : @trajectory.TimeAxis,
) -> @html.Html {
  let lines : Array[@html.Html] = []
  for tick in ticks {
    lines.push(
      @html.div(
        class=if tick.is_day {
          "waterfall-grid-line day"
        } else {
          "waterfall-grid-line"
        },
        style=["left: \{round1(tick_percent(tick, axis))}%"],
      ) <| "",
    )
  }
  @html.div(class="waterfall-grid") <| [
    @html.div(class="waterfall-grid-pad") <| "",
    @html.div(class="waterfall-grid-track") <| lines,
    @html.div(class="waterfall-grid-pad") <| "",
  ]
}

///|
/// One background job's log, opened under the row that named it: the state the
/// job ended in, then the text it wrote.
///
/// The text comes from the job's own file, not from the session log — a job can
/// print megabytes the transcript never carries. A long log is read from its
/// tail, and the block says so rather than pretending to show the beginning.
fn job_log_block(
  emit : @cmd.Emit[Msg],
  model : Model,
  span : @trajectory.TrajectorySpan,
  key : String,
) -> @html.Html {
  let panel = match model.trajectory_jobs.get(key) {
    Some(panel) => panel
    None => Loading
  }
  let indent = span.depth * 14 + 24
  @html.div(class="job-log", style=["margin-left: \{indent}px"]) <| [
    @html.div(class="job-log-head") <| [
      @html.span(class="job-log-title") <| job_log_title(panel, key),
      @html.button(
        class="job-log-close",
        title="Hide this job's output",
        on_click=emit(ToggleJobLog(key)),
      ) <| "Hide",
    ],
    ..job_log_body(panel),
  ]
}

///|
/// What the block's header says: which job, how it ended, and how much it
/// wrote. The job id stays in the header so a reader who scrolled past the row
/// still knows which one this is.
fn job_log_title(panel : JobPanel, key : String) -> String {
  let job_id = job_id_of_key(key)
  match panel {
    Loading => "job \{job_id} · reading its log…"
    Missing(_) => "job \{job_id}"
    Shown(log) => {
      let state = job_state_label(log.summary.state, log.summary.exit_code)
      "job \{job_id} · \{state} · \{job_bytes_label(log.summary.output_bytes)}"
    }
  }
}

///|
/// How a job ended, in the words the panel uses: a finished job carries its
/// exit code, because `exited 0` and `exited 2` are the difference a reader is
/// looking for.
fn job_state_label(state : String, exit_code : Int32?) -> String {
  match (state, exit_code) {
    ("exited", Some(code)) => "exited \{code}"
    (_, Some(code)) => "\{state} \{code}"
    _ => state
  }
}

///|
/// A byte count in the unit a reader can hold: job logs run from a few lines to
/// tens of megabytes.
fn job_bytes_label(bytes : Int64) -> String {
  let value = bytes.to_double()
  if bytes < 1_024L {
    "\{bytes} B"
  } else if bytes < 1_048_576L {
    "\{round1(value / 1_024.0)} KB"
  } else {
    "\{round1(value / 1_048_576.0)} MB"
  }
}

///|
/// The block below the header: the log itself, or why there is none.
fn job_log_body(panel : JobPanel) -> Array[@html.Html] {
  let alert = why => {
    @html.div(class="job-log-error", attrs=@html.Attrs::build().role("alert")) <| why
  }
  match panel {
    Loading => [@html.div(class="job-log-status") <| "reading…"]
    // A missing record is an error, not an empty log: the two look alike on
    // screen otherwise, and the reader would keep waiting for text.
    Missing(why) => [alert(why)]
    Shown(log) =>
      match log.problem {
        Some(why) => [alert(why)]
        None => {
          let notes : Array[@html.Html] = []
          if log.head_omitted {
            notes.push(
              @html.div(class="job-log-note") <| "earlier output is not shown: this is the tail of \{job_bytes_label(log.size)}",
            )
          }
          if log.summary.output_truncated {
            notes.push(
              @html.div(class="job-log-note") <| "the engine stopped keeping this job's whole log",
            )
          }
          if log.summary.invalid_utf8 {
            notes.push(
              @html.div(class="job-log-note") <| "the log holds bytes that are not text; they read as replacement characters",
            )
          }
          if log.text.is_blank() {
            notes.push(@html.div(class="job-log-status") <| "no output yet")
          }
          let body : Array[@html.Html] = []
          if !log.text.is_blank() {
            body.push(@html.pre(class="job-log-text") <| log.text)
          }
          body.append(notes)
          body
        }
      }
  }
}
