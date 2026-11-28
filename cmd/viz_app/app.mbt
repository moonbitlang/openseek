///|
/// One row of the `/api/sessions` listing shown in the sidebar. The server
/// already returns rows most-recently-active first; the row keeps `last_active`
/// so the sidebar can show when an experiment last wrote to disk.
#derive(Eq)
struct SessionRow {
  key : String
  id : String
  root_label : String
  run_root : String?
  last_active : Int64?
  // Whether the server discovered this root as a marker store (a `.openseek`-like
  // directory) rather than a direct `--session-root` store. Drives whether the
  // sidebar strips the last path segment when grouping. Absent → `false`.
  is_marker : Bool
  first_prompt : String
}

///|
/// The whole viewer state. The current session is kept as the parsed log plus a
/// system prompt lifted from the session file's header line; the typed
/// `Session` and its model projection are rebuilt in `view` so the two view
/// modes always agree with the bytes on disk.
#derive(Eq)
struct Model {
  sessions : Array[SessionRow]
  selected : String?
  // Session key parsed from the URL hash at startup, waiting for the first
  // session listing so a refresh can land back on the same session. Consumed
  // (set to None) by the first `SessionsFetched`.
  pending_restore_key : String?
  // Name of a locally dropped session file being viewed instead of a server
  // session. Mutually exclusive with `selected`.
  dropped : String?
  // Monotonic ticket for dropped-file reads. Every new drop and every session
  // selection advances it, so a read that finishes after the user moved on
  // carries a stale ticket and is discarded.
  drop_ticket : Int32
  parsed : @session_log.ParsedLog?
  system_prompt : String
  header_present : Bool
  log_bytes : Int64
  view_mode : @viz.ViewMode
  theme : Theme
  sidebar_visible : Bool
  collapsed_roots : Array[String]
  loading : Bool
  status : String
  // "Errors only" filter folds the log down to failed tool results.
  errors_only : Bool
  // "Escalated only" keeps tool calls whose durable arguments explicitly carry
  // top-level `escalated: true`, plus their matching result cards.
  escalated_only : Bool
  // "Build errors only" keeps mbtx calls whose result brief reports a
  // BUILD-stage failure, plus their matching result cards.
  build_errors_only : Bool
  // Tool-call arguments rendering: the human-friendly form (values shown verbatim,
  // no JSON quoting) by default, or the original pretty-printed JSON for debugging.
  show_original_args : Bool
  // Child sessions (subagent transcripts) loaded for the selected parent,
  // keyed by child session id — rendered inline inside the parent's subrun
  // tool cards. Cleared on every selection change.
  subrun_children : Map[String, @agent_session.Session]
  // `inspect --watch` polling interval in milliseconds; 0 when not watching
  // (no `--watch`, or a standalone export).
  watch_ms : Int32
  // A watch refresh of the open session is in flight; the next tick waits.
  watch_pending : Bool
  // Ticks since startup, to refresh the session list less often than the
  // open session.
  watch_ticks : Int32
  // The run whose waterfall is open (`#t=<session id>`), the trace itself, and
  // a ticket guarding against a slow response for a run the reader left. All
  // three are independent of `selected`: the trajectory page outlives the
  // session selection it was opened from.
  trajectory_root : String?
  trajectory : @trajectory.Trajectory?
  trajectory_ticket : Int32
  trajectory_pending : Bool
  trajectory_error : String?
  // The cursor the last trajectory reply carried. A poll sends it back, and a
  // run that has not moved answers `unchanged` instead of the whole document.
  trajectory_cursor : String?
  // Span ids whose subtree the reader folded away. A long run has hundreds of
  // steps, and folding a finished turn is how a reader gets to the part that
  // matters.
  trajectory_collapsed : Array[String]
  // Draw the waterfall with idle stretches folded (the default) or at true
  // scale. A run saved across a night is almost entirely idle.
  trajectory_compact : Bool
  // Keep only the failed steps and the ancestors that place them. A run of
  // thousands of spans needs the same cut the log view already offers.
  trajectory_failed_only : Bool
  // Background jobs whose log the reader opened in place, by
  // `session/job` key, and the log itself once it arrives. Kept across a poll:
  // a live run re-folds every second, and a job the reader is reading must not
  // close under them.
  trajectory_job_open : Array[String]
  trajectory_jobs : Map[String, JobPanel]
  // Keys with a job-log request currently in flight, preventing overlapping
  // watch polls from issuing duplicate cursor reads.
  trajectory_job_pending : Array[String]
  // Job id and optional start hint requested via `#t=<root>&job=<id>[&start=<ms>]`
  // waiting to be focused once the trace loads, plus resolved span id.
  trajectory_focus_job : String?
  trajectory_focus_job_start : Int64?
  trajectory_focus_span : String?
  // Whether the open trajectory fetch asked `inspect` to resolve a child
  // session id up to its store root (`?resolve_root=1`).
  trajectory_resolve_root : Bool
  // Virtual-scroll window state for large waterfalls.
  trajectory_scroll_top : Int32
  trajectory_viewport_h : Int32
  // A frozen `--export` archive: API answers are baked into
  // `window.__OPENSEEK_DATA__`, so the waterfall opens only runs that were
  // baked and omits live `.out` job logs.
  standalone : Bool
}

///|
/// Colour theme. `System` is the default and follows the OS via a CSS
/// `prefers-color-scheme` media query (so it tracks live OS changes without any
/// listener). The choice is applied by setting `data-theme` on `<html>`.
#derive(Eq)
enum Theme {
  Light
  Dark
  System
}

///|
fn Theme::value(self : Theme) -> String {
  match self {
    Light => "light"
    Dark => "dark"
    System => "system"
  }
}

///|
/// Messages driving the update loop. The `String` in the fetch results carries
/// the session id the request was issued for, so a slow response for a session
/// the user already navigated away from is discarded instead of clobbering the
/// pane.
enum Msg {
  SessionsFetched(Result[String, Error])
  Select(String)
  SessionFetched(String, Result[String, Error])
  // Rabbita captured an anchor click. Only internal `#s=…` requests belong to
  // this viewer; other anchors keep their existing handling.
  UrlRequested(@url.UrlRequest)
  // A URL pushed by the request handler, or restored through browser history.
  UrlChanged(@url.Url)
  // One child (subagent) session fetched for the selected parent:
  // (parent key, child session id, response).
  SubrunFetched(String, String, Result[String, Error])
  FileDropped(String, Int64, @dom.Blob)
  DroppedFileRead(Int32, String, Int64, Result[String, Error])
  SetMode(@viz.ViewMode)
  SetArgsView(Bool)
  SetTheme(Theme)
  ToggleSidebar
  ToggleRoot(String)
  ToggleErrorsOnly
  JumpToError(Int32)
  ToggleEscalatedOnly
  JumpToEscalated(Int32)
  ToggleBuildErrorsOnly
  JumpToBuildError(Int32)
  UnfoldCurrent
  // `--watch`: time to re-check the open session (and now and then the list).
  WatchTick
  // A watch re-check of the open session: (session key, response).
  WatchFetched(String, Result[String, Error])
  // A watch refresh of the session list. Unlike `SessionsFetched` it leaves
  // the status line and the selection alone.
  WatchSessionsFetched(Result[String, Error])
  // Open one run's waterfall. The id is a session id, not a catalog key: a run
  // spans several files.
  OpenTrajectory(String)
  CloseTrajectory
  /// Fold or unfold the subtree of one span.
  ToggleTrajectorySpan(String)
  /// Scroll to the first failed step of the open waterfall.
  JumpToFirstFailure
  /// Switch the waterfall's time axis between folded and true-scale idle.
  ToggleTrajectoryAxis
  /// Keep only the failed steps (and the rows that place them), or show them all.
  ToggleTrajectoryFailures
  /// Open or close one background job's log, in place under its row.
  ToggleJobLog(String)
  // One job-log fetch: (key, the cursor it continued from, response).
  JobLogFetched(String, Int64?, Result[String, Error])
  // One trace fetch: (root id, ticket, response).
  TrajectoryFetched(String, Int32, Result[String, Error])
  /// Virtual-scroll viewport update for `.waterfall-body`.
  TrajectoryScroll(Int32, Int32)
}

///|
/// Outcome of decoding the `/api/sessions/<id>` envelope. `rabbita/http` reports
/// any completed response as `Ok`, so absence and malformed payloads are
/// distinguished here from the body, not the HTTP status.
enum LoadOutcome {
  Loaded(@session_log.ParsedLog, String, Bool, Int64)
  // A watch re-check found the log still at the size the viewer already has.
  Unchanged
  NotFound
  Malformed
}

///|
/// A standalone archive is primarily a complete durable trace, so open it on
/// the append-only raw log. The live viewer keeps its established model-view
/// default for inspecting the context sent to the next request.
fn initial_view_mode(standalone : Bool) -> @viz.ViewMode {
  if standalone {
    RawLog
  } else {
    ModelView
  }
}

///|
/// Whether the freshly fetched session list should auto-open its first entry:
/// standalone exports only, at least one session, and nothing already on
/// screen (a selection in flight or a dropped file must not be clobbered).
fn should_auto_open(
  standalone : Bool,
  sessions : Array[SessionRow],
  selected~ : String?,
  dropped~ : String?,
) -> Bool {
  standalone && !sessions.is_empty() && selected is None && dropped is None
}

///|
/// The view mode to start in: an explicit `v=` in the URL hash (a restored
/// refresh) wins over the standalone/live defaults.
fn restored_view_mode(hash_view : String?, standalone : Bool) -> @viz.ViewMode {
  match hash_view {
    Some("raw") => RawLog
    Some("model") => ModelView
    _ => initial_view_mode(standalone)
  }
}

///|
/// The hash spelling of a view mode (the `v=` value the scrollspy state keeps).
fn view_mode_value(mode : @viz.ViewMode) -> String {
  match mode {
    RawLog => "raw"
    ModelView => "model"
  }
}

///|
fn parse_optional_int64(value : String?) -> Int64? {
  guard value is Some(text) && !text.is_empty() else { return None }
  let chars = text.to_array()
  let mut idx = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    idx = 1
  }
  guard idx < chars.length() else { return None }
  let max_int64 = 9223372036854775807L
  let mut acc = 0L
  while idx < chars.length() {
    let ch = chars[idx]
    guard ch.is_ascii_digit() else { return None }
    let digit = (ch.to_int() - '0'.to_int()).to_int64()
    if acc > (max_int64 - digit) / 10L {
      return None
    }
    acc = acc * 10L + digit
    idx += 1
  }
  Some(if negative { -acc } else { acc })
}

///|
fn init_model() -> Model {
  let initial_trajectory_root = hash_param("t")
  let initial_focus_start = parse_optional_int64(hash_param("start"))
  let initial_resolve_root = hash_param("resolve") is Some("1")
  {
    sessions: [],
    selected: None,
    pending_restore_key: match hash_param("s") {
      Some("") | None => None
      Some(key) => Some(key)
    },
    dropped: None,
    drop_ticket: 0,
    parsed: None,
    system_prompt: "",
    header_present: false,
    log_bytes: 0L,
    view_mode: restored_view_mode(
      hash_param("v"),
      embedded_has("/api/sessions"),
    ),
    theme: System,
    sidebar_visible: true,
    collapsed_roots: [],
    loading: false,
    status: "loading sessions…",
    errors_only: false,
    build_errors_only: false,
    escalated_only: false,
    show_original_args: false,
    subrun_children: Map([]),
    trajectory_collapsed: [],
    trajectory_compact: true,
    trajectory_failed_only: false,
    trajectory_job_open: [],
    trajectory_jobs: Map([]),
    trajectory_job_pending: [],
    trajectory_focus_job: match hash_param("job") {
      Some("") | None => None
      Some(id) => Some(id)
    },
    trajectory_focus_job_start: initial_focus_start,
    trajectory_focus_span: None,
    trajectory_resolve_root: initial_resolve_root,
    trajectory_scroll_top: 0,
    trajectory_viewport_h: 900,
    standalone: embedded_has("/api/sessions"),
    // An export is a frozen archive; only a served viewer can watch.
    watch_ms: if embedded_has("/api/sessions") {
      0
    } else {
      watch_interval_ms()
    },
    watch_pending: false,
    watch_ticks: 0,
    // A refresh of `#t=<root>` reopens the waterfall straight away.
    trajectory_root: initial_trajectory_root,
    trajectory: None,
    trajectory_ticket: if initial_trajectory_root is Some(_) {
      1
    } else {
      0
    },
    trajectory_pending: initial_trajectory_root is Some(_),
    trajectory_error: None,
    trajectory_cursor: None,
  }
}

///|
/// How many watch ticks pass between session-list refreshes. The list scan
/// reads every log's first prompt, so it runs less often than the open
/// session's cheap size check.
fn clear_trajectory_hash() -> Unit {
  remove_hash_value("t")
  remove_hash_value("job")
  remove_hash_value("start")
  remove_hash_value("resolve")
}

///|
fn clear_trajectory_state(model : Model) -> Model {
  {
    ..model,
    trajectory_root: None,
    trajectory: None,
    trajectory_pending: false,
    trajectory_error: None,
    trajectory_cursor: None,
    trajectory_collapsed: [],
    trajectory_failed_only: false,
    trajectory_job_open: [],
    trajectory_jobs: Map([]),
    trajectory_job_pending: [],
    trajectory_focus_job: None,
    trajectory_focus_job_start: None,
    trajectory_focus_span: None,
    trajectory_resolve_root: false,
  }
}

///|
fn open_trajectory_from_fragment(
  emit : @cmd.Emit[Msg],
  model : Model,
  fragment : String,
) -> (@cmd.Cmd, Model)? {
  guard HashTrajectoryRoot::from_fragment(fragment) is Some(root) else {
    return None
  }
  let focus_job = hash_fragment_param(fragment, "job")
  let focus_start = parse_optional_int64(hash_fragment_param(fragment, "start"))
  let resolve_root = hash_fragment_param(fragment, "resolve") is Some("1")
  if model.trajectory_root == Some(root.0) && focus_job is None && !resolve_root {
    return Some((@cmd.none, model))
  }
  Some(
    update(emit, OpenTrajectory(root.0), {
      ..model,
      trajectory_focus_job: focus_job,
      trajectory_focus_job_start: focus_start,
      trajectory_resolve_root: resolve_root,
    }),
  )
}

///|
let watch_list_every : Int32 = 5

// ---- update ----------------------------------------------------------------

///|
fn update(emit : @cmd.Emit[Msg], msg : Msg, model : Model) -> (@cmd.Cmd, Model) {
  match msg {
    SessionsFetched(Ok(text)) =>
      match parse_session_rows(text) {
        Some(sessions) => {
          let untouched = model.selected is None && model.dropped is None
          // A watching viewer opened on a session that has not written its
          // first event yet (a run's own link, printed as it starts) keeps
          // the key and opens it once a list refresh shows it.
          let waiting_for = match model.pending_restore_key {
            Some(key) if model.watch_ms > 0 &&
              untouched &&
              resolve_session_key(sessions, key) is None => Some(key)
            _ => None
          }
          let listed = {
            ..model,
            sessions,
            pending_restore_key: waiting_for,
            collapsed_roots: prune_collapsed_roots(
              model.collapsed_roots,
              sessions,
            ),
            status: match waiting_for {
              Some(key) => "waiting for \{key} to start…"
              None => list_status(model, "\{sessions.length()} session(s)")
            },
          }
          // A refresh restores the session named in the URL hash — in the
          // live viewer and in exports alike. Otherwise a standalone export
          // opens the first row immediately. Desktop session-family exports
          // put the parent first; live servers keep the explicit click, since
          // their list refreshes must never yank the user off a session.
          match model.pending_restore_key {
            Some(key) if untouched &&
              resolve_session_key(sessions, key) is Some(resolved) =>
              update(emit, Select(resolved), listed)
            _ =>
              if should_auto_open(
                  embedded_has("/api/sessions"),
                  sessions,
                  selected=model.selected,
                  dropped=model.dropped,
                ) {
                update(emit, Select(sessions[0].key), listed)
              } else {
                (@cmd.none, listed)
              }
          }
        }
        None =>
          (
            @cmd.none,
            {
              ..model,
              status: list_status(model, "could not read the session list"),
            },
          )
      }
    SessionsFetched(Err(error)) =>
      (
        @cmd.none,
        {
          ..model,
          status: list_status(model, "failed to list sessions: \{error}"),
        },
      )
    Select(key) => {
      let label = session_label(model, key)
      let command = fetch_text(emit, session_url(key), result => {
        SessionFetched(key, result)
      })
      // Record the selection in the URL hash so a refresh lands back here.
      // Selecting a different session drops the stale seq= position (the
      // extern compares keys); re-selecting the same one keeps it.
      // Leaving the waterfall by picking a session must also drop its `t=`, or a
      // refresh would reopen the page the reader just left.
      let leaving_trajectory = model.trajectory_root is Some(_)
      let mode = view_mode_value(model.view_mode)
      (
        @cmd.batch([
          command,
          @cmd.effect(() => {
            set_hash_session(key, mode)
            if leaving_trajectory {
              clear_trajectory_hash()
            }
          }),
        ]),
        clear_trajectory_state({
          ..model,
          selected: Some(key),
          dropped: None,
          // Invalidate any in-flight dropped-file read.
          drop_ticket: model.drop_ticket + 1,
          parsed: None,
          system_prompt: "",
          header_present: false,
          log_bytes: 0L,
          loading: true,
          status: "loading \{label}…",
          subrun_children: Map([]),
        }),
      )
    }
    OpenTrajectory(root) => {
      let ticket = model.trajectory_ticket + 1
      (
        trajectory_fetch(
          emit,
          root,
          ticket,
          resolve_root=model.trajectory_resolve_root,
        ),
        {
          ..model,
          trajectory_root: Some(root),
          trajectory: None,
          trajectory_collapsed: [],
          trajectory_failed_only: false,
          trajectory_job_open: [],
          trajectory_jobs: Map([]),
          trajectory_job_pending: [],
          trajectory_focus_span: None,
          trajectory_scroll_top: 0,
          trajectory_ticket: ticket,
          trajectory_pending: true,
          trajectory_error: None,
          trajectory_cursor: None,
          status: "loading trajectory for \{root}…",
        },
      )
    }
    CloseTrajectory =>
      (
        @cmd.effect(() => clear_trajectory_hash()),
        clear_trajectory_state(model),
      )
    ToggleTrajectoryAxis =>
      (@cmd.none, { ..model, trajectory_compact: !model.trajectory_compact, })
    ToggleTrajectoryFailures => {
      let enabling = !model.trajectory_failed_only
      let collapsed = if enabling {
        match model.trajectory {
          Some(trace) =>
            unfold_failed_ancestors(trace, model.trajectory_collapsed)
          None => model.trajectory_collapsed
        }
      } else {
        model.trajectory_collapsed
      }
      (
        @cmd.none,
        {
          ..model,
          trajectory_failed_only: enabling,
          trajectory_collapsed: collapsed,
        },
      )
    }
    ToggleJobLog(key) =>
      if model.trajectory_job_open.contains(key) {
        (
          @cmd.none,
          {
            ..model,
            trajectory_job_open: model.trajectory_job_open.filter(open => {
              open != key
            }),
          },
        )
      } else {
        // Opening caches nothing twice: a panel already read stays as it was,
        // so folding a row away and back does not re-fetch a finished job.
        let open = model.trajectory_job_open.copy()
        open.push(key)
        let (command, jobs, pending) = match model.trajectory_jobs.get(key) {
          Some(_) =>
            (@cmd.none, model.trajectory_jobs, model.trajectory_job_pending)
          None => {
            let jobs = model.trajectory_jobs.copy()
            jobs[key] = Loading
            if model.trajectory_job_pending.contains(key) {
              (@cmd.none, jobs, model.trajectory_job_pending)
            } else {
              let pending = model.trajectory_job_pending.copy()
              pending.push(key)
              (
                job_log_fetch(emit, key, model.trajectory, cursor?=None),
                jobs,
                pending,
              )
            }
          }
        }
        (
          command,
          {
            ..model,
            trajectory_job_open: open,
            trajectory_jobs: jobs,
            trajectory_job_pending: pending,
          },
        )
      }
    JobLogFetched(key, cursor, result) => {
      let pending = model.trajectory_job_pending.filter(item => item != key)
      let previous = match model.trajectory_jobs.get(key) {
        Some(panel) => panel
        None => Loading
      }
      let panel = match result {
        Ok(text) =>
          match parse_job_reply(text) {
            Some(reply) => job_panel_after(previous, cursor, reply)
            None => Missing("this viewer cannot read the job reply")
          }
        Err(_) => Missing("could not read this job's log")
      }
      let jobs = model.trajectory_jobs.copy()
      jobs[key] = panel
      // A cursor the file outgrew puts the panel back to `Loading`; read the
      // tail again rather than leave the row spinning.
      let (reread, next_pending) = if panel is Loading && cursor is Some(_) {
        let next_pending = pending.copy()
        next_pending.push(key)
        (job_log_fetch(emit, key, model.trajectory, cursor?=None), next_pending)
      } else {
        (@cmd.none, pending)
      }
      (
        reread,
        {
          ..model,
          trajectory_jobs: jobs,
          trajectory_job_pending: next_pending,
        },
      )
    }
    ToggleTrajectorySpan(id) => {
      let folded = model.trajectory_collapsed.contains(id)
      (
        @cmd.none,
        {
          ..model,
          trajectory_collapsed: if folded {
            model.trajectory_collapsed.filter(open_id => open_id != id)
          } else {
            [..model.trajectory_collapsed, id]
          },
        },
      )
    }
    TrajectoryFetched(root, ticket, result) =>
      // A response for a run the reader already left cannot replace the one on
      // screen.
      if model.trajectory_root != Some(root) ||
        model.trajectory_ticket != ticket {
        (@cmd.none, model)
      } else {
        match result {
          Err(_) =>
            (
              @cmd.none,
              {
                ..model,
                trajectory_pending: false,
                trajectory_error: Some("could not load the trajectory"),
                status: "could not load the trajectory for \{root}",
              },
            )
          Ok(text) =>
            match parse_trajectory_reply(text) {
              // Nothing moved since the cursor we sent: keep the trace on
              // screen instead of re-parsing an identical document.
              Some(Unchanged) =>
                (
                  @cmd.none,
                  {
                    ..model,
                    trajectory_pending: false,
                    trajectory_error: None,
                  },
                )
              Some(Trace(trace, cursor)) => {
                let mut next_collapsed = if model.trajectory is None &&
                  model.trajectory_collapsed.is_empty() &&
                  model.trajectory_focus_job is None {
                  auto_collapsed_turns(trace)
                } else {
                  model.trajectory_collapsed
                }
                let mut next_focus_span = model.trajectory_focus_span
                let mut next_focus_job = model.trajectory_focus_job
                let mut next_focus_start = model.trajectory_focus_job_start
                let mut next_scroll_top = model.trajectory_scroll_top
                let next_open = model.trajectory_job_open.copy()
                let next_jobs = model.trajectory_jobs.copy()
                let next_job_pending = model.trajectory_job_pending.copy()
                let effects : Array[@cmd.Cmd] = []
                if model.trajectory_resolve_root ||
                  trace.root_session_id != root {
                  let resolved_root = trace.root_session_id
                  effects.push(
                    @cmd.effect(() => normalize_trajectory_hash(resolved_root)),
                  )
                }
                if model.trajectory_focus_job is Some(job_id) {
                  let start_hint = next_focus_start
                  next_focus_job = None
                  next_focus_start = None
                  if find_job_focus_span(trace, job_id, start_hint?)
                    is Some(span) {
                    next_focus_span = Some(span.id)
                    next_collapsed = unfold_span_ancestors(
                      trace,
                      next_collapsed,
                      span.id,
                    )
                    if find_span_row_index(
                        trace,
                        next_collapsed,
                        model.trajectory_failed_only,
                        span.id,
                      )
                      is Some(idx) {
                      let est = idx * WaterfallRowHeightPx -
                        model.trajectory_viewport_h / 2
                      next_scroll_top = if est > 0 { est } else { 0 }
                      effects.push(
                        @cmd.effect(() => {
                          scroll_to_waterfall_row(idx, WaterfallRowHeightPx)
                        }),
                      )
                    } else {
                      effects.push(@cmd.effect(() => scroll_to_focused_job()))
                    }
                    let key = job_panel_key(span.session_id, job_id)
                    if job_log_available(model, key) {
                      if !next_open.contains(key) {
                        next_open.push(key)
                      }
                      if next_jobs.get(key) is None &&
                        !next_job_pending.contains(key) {
                        next_jobs[key] = Loading
                        next_job_pending.push(key)
                        effects.push(
                          job_log_fetch(
                            emit,
                            key,
                            Some(trace),
                            preferred_span_id=span.id,
                            start_hint?,
                            cursor?=None,
                          ),
                        )
                      }
                    }
                  }
                }
                (
                  @cmd.batch(effects),
                  {
                    ..model,
                    trajectory_root: Some(trace.root_session_id),
                    trajectory_resolve_root: false,
                    trajectory: Some(trace),
                    trajectory_cursor: cursor,
                    trajectory_pending: false,
                    trajectory_error: None,
                    trajectory_collapsed: next_collapsed,
                    trajectory_focus_job: next_focus_job,
                    trajectory_focus_job_start: next_focus_start,
                    trajectory_focus_span: next_focus_span,
                    trajectory_scroll_top: next_scroll_top,
                    trajectory_job_open: next_open,
                    trajectory_jobs: next_jobs,
                    trajectory_job_pending: next_job_pending,
                    status: "\{trace.stats.span_count} span(s) from \{trace.stats.session_count} session(s)",
                  },
                )
              }
              None =>
                (
                  @cmd.none,
                  {
                    ..model,
                    trajectory_pending: false,
                    trajectory_error: Some("malformed trajectory response"),
                    status: "malformed trajectory response for \{root}",
                  },
                )
            }
        }
      }
    JumpToFirstFailure => {
      let collapsed = match model.trajectory {
        Some(trace) =>
          unfold_failed_ancestors(trace, model.trajectory_collapsed)
        None => model.trajectory_collapsed
      }
      match
        model.trajectory.bind(trace => {
          find_first_failure_row_index(
            trace,
            collapsed,
            model.trajectory_failed_only,
          )
        }) {
        Some(idx) => {
          let est = idx * WaterfallRowHeightPx - model.trajectory_viewport_h / 2
          let next_scroll_top = if est > 0 { est } else { 0 }
          (
            @cmd.effect(() => scroll_to_waterfall_row(idx, WaterfallRowHeightPx)),
            {
              ..model,
              trajectory_collapsed: collapsed,
              trajectory_scroll_top: next_scroll_top,
            },
          )
        }
        None =>
          (
            @cmd.effect(() => scroll_to_first_failure()),
            { ..model, trajectory_collapsed: collapsed, },
          )
      }
    }
    TrajectoryScroll(top, vh) => {
      let stride = WaterfallRowHeightPx * 4
      if (top - model.trajectory_scroll_top).abs() >= stride ||
        (vh - model.trajectory_viewport_h).abs() >= stride ||
        (top == 0 && model.trajectory_scroll_top != 0) {
        (
          @cmd.none,
          { ..model, trajectory_scroll_top: top, trajectory_viewport_h: vh, },
        )
      } else {
        (@cmd.none, model)
      }
    }
    UrlRequested(request) =>
      match request {
        Internal(url) =>
          match url.fragment {
            Some(fragment) =>
              match open_trajectory_from_fragment(emit, model, fragment) {
                Some((command, next)) =>
                  (@cmd.batch([@nav.push_url(url.to_string()), command]), next)
                None =>
                  try HashSessionKey::from_fragment(fragment) catch {
                    MalformedHashSessionKey =>
                      (
                        @cmd.none,
                        {
                          ..model,
                          status: "invalid session link: malformed s= value",
                        },
                      )
                  } noraise {
                    Some(_) => (@nav.push_url(url.to_string()), model)
                    None => (@cmd.none, model)
                  }
              }
            None => (@cmd.none, model)
          }
        External(_) => (@cmd.none, model)
      }
    UrlChanged(url) =>
      match url.fragment {
        Some(fragment) =>
          match open_trajectory_from_fragment(emit, model, fragment) {
            Some(result) => result
            None =>
              try HashSessionKey::from_fragment(fragment) catch {
                MalformedHashSessionKey =>
                  (
                    @cmd.none,
                    {
                      ..model,
                      status: "invalid session link: malformed s= value",
                    },
                  )
              } noraise {
                Some(key) =>
                  // Resolve like startup restoration; unknown anchors do not
                  // clear the current session.
                  match resolve_session_key(model.sessions, key.0) {
                    Some(key) if model.selected != Some(key) =>
                      update(emit, Select(key), model)
                    _ => (@cmd.none, model)
                  }
                None => (@cmd.none, model)
              }
          }
        None => (@cmd.none, model)
      }
    SubrunFetched(parent_key, child_id, result) =>
      // A child transcript for a parent the user already left is stale;
      // a failed or malformed child fetch simply leaves the chip link-only.
      if model.selected != Some(parent_key) {
        (@cmd.none, model)
      } else {
        match result {
          Err(_) => (@cmd.none, model)
          Ok(text) =>
            match parse_load(text) {
              Loaded(parsed, system_prompt, _header_present, _bytes) => {
                let children : Map[String, @agent_session.Session] = Map([])
                for id, child in model.subrun_children {
                  children.set(id, child)
                }
                children.set(
                  child_id,
                  @viz.session_from_parse(parsed, id=child_id, system_prompt~),
                )
                (@cmd.none, { ..model, subrun_children: children, })
              }
              Unchanged | NotFound | Malformed => (@cmd.none, model)
            }
        }
      }
    SessionFetched(key, result) =>
      // Drop a response for a session the user already navigated away from.
      if model.selected != Some(key) {
        (@cmd.none, model)
      } else {
        let label = session_label(model, key)
        match result {
          Err(error) =>
            (
              @cmd.none,
              { ..model, loading: false, status: "request failed: \{error}", },
            )
          Ok(text) =>
            match parse_load(text) {
              Loaded(parsed, system_prompt, header_present, log_bytes) => {
                // Prefetch any subagent transcripts this session references
                // (subrun briefs → sibling sessions in the listing), so the
                // raw view can nest them inline as they arrive.
                let child_fetches = subrun_child_refs(model, key, parsed).map(child => {
                  let (child_id, child_key) = child
                  fetch_text(emit, session_url(child_key), result => {
                    SubrunFetched(key, child_id, result)
                  })
                })
                (
                  // The log renders in this same cycle; once it is in the
                  // DOM, scroll back to the seq= position saved in the hash.
                  @cmd.batch(
                    [
                      @cmd.effect(() => restore_scroll_to_hash_seq()),
                      ..child_fetches,
                    ],
                  ),
                  {
                    ..model,
                    parsed: Some(parsed),
                    system_prompt,
                    header_present,
                    log_bytes,
                    loading: false,
                    status: events_status(parsed),
                  },
                )
              }
              NotFound =>
                (
                  @cmd.none,
                  {
                    ..model,
                    parsed: None,
                    loading: false,
                    status: "session not found: \{label}",
                  },
                )
              // Only a watch request sends `known_bytes`, so a plain load
              // never sees this; treat it like any other unusable reply.
              Unchanged | Malformed =>
                (
                  @cmd.none,
                  {
                    ..model,
                    parsed: None,
                    loading: false,
                    status: "malformed response for \{label}",
                  },
                )
            }
        }
      }
    WatchTick => {
      let ticks = model.watch_ticks + 1
      // While a linked session has yet to appear, look for it every tick.
      let list_refresh = if ticks % watch_list_every == 0 ||
        model.pending_restore_key is Some(_) {
        [
          fetch_text(emit, "/api/sessions", result => {
            WatchSessionsFetched(result)
          }),
        ]
      } else {
        []
      }
      // An open waterfall follows the run: a live trace is re-read every tick,
      // a settled or failed trace is re-checked every few ticks (with cursor),
      // and an in-flight request is never overlapped.
      let (trajectory_refresh, next_trajectory_pending) = if model.trajectory_pending {
        ([], true)
      } else {
        match (model.trajectory_root, model.trajectory) {
          (Some(root), Some(trace)) =>
            if trace.live || ticks % watch_list_every == 0 {
              (
                [
                  trajectory_fetch(
                    emit,
                    root,
                    model.trajectory_ticket,
                    cursor?=model.trajectory_cursor,
                  ),
                ],
                true,
              )
            } else {
              ([], false)
            }
          (Some(root), None) =>
            if model.trajectory_error is None || ticks % watch_list_every == 0 {
              ([trajectory_fetch(emit, root, model.trajectory_ticket)], true)
            } else {
              ([], false)
            }
          (None, _) => ([], false)
        }
      }
      let list_refresh = [..trajectory_refresh, ..list_refresh]
      // An open job log follows its own file while the job runs, from the byte
      // offset the last page ended at, skipping keys already in flight.
      let next_job_pending = model.trajectory_job_pending.copy()
      let job_refresh : Array[@cmd.Cmd] = []
      for key in model.trajectory_job_open {
        if next_job_pending.contains(key) {
          continue
        }
        if model.trajectory_jobs.get(key) is Some(panel) &&
          job_log_wants_more(panel) {
          let cursor = match panel {
            Shown(log) => Some(log.next_offset)
            _ => None
          }
          next_job_pending.push(key)
          job_refresh.push(job_log_fetch(emit, key, model.trajectory, cursor?))
        }
      }
      let list_refresh = [..job_refresh, ..list_refresh]
      let next_model = {
        ..model,
        watch_ticks: ticks,
        trajectory_pending: next_trajectory_pending,
        trajectory_job_pending: next_job_pending,
      }
      match model.selected {
        // Re-check only a settled server session: not while its first load
        // or a previous re-check is still in flight.
        Some(key) if !model.loading && !model.watch_pending =>
          (
            @cmd.batch(
              [
                fetch_text(
                  emit,
                  "\{session_url(key)}?known_bytes=\{model.log_bytes}",
                  result => WatchFetched(key, result),
                ),
                ..list_refresh,
              ],
            ),
            { ..next_model, watch_pending: true, },
          )
        _ => (@cmd.batch(list_refresh), next_model)
      }
    }
    WatchFetched(key, result) => {
      let model = { ..model, watch_pending: false, }
      // The user moved on while this was in flight; the new selection loads
      // itself.
      guard model.selected == Some(key) && !model.loading else {
        return (@cmd.none, model)
      }
      match result {
        // A transient failure (the server restarting, say) must not blank a
        // session that is still on screen; the next tick tries again.
        Err(_) => (@cmd.none, model)
        Ok(text) =>
          match parse_load(text) {
            Unchanged | Malformed => (@cmd.none, model)
            NotFound =>
              (
                @cmd.none,
                {
                  ..model,
                  status: "session no longer on disk: \{session_label(model, key)}",
                },
              )
            Loaded(parsed, system_prompt, header_present, log_bytes) => {
              // Decide before the new events render: a reader parked at the
              // bottom follows the log, anyone scrolled up stays put.
              let follow = main_scrolled_to_bottom()
              let child_fetches = subrun_child_refs(model, key, parsed).map(child => {
                let (child_id, child_key) = child
                fetch_text(emit, session_url(child_key), result => {
                  SubrunFetched(key, child_id, result)
                })
              })
              let scroll = if follow {
                [@cmd.effect(() => scroll_main_to_bottom())]
              } else {
                []
              }
              (
                @cmd.batch([..scroll, ..child_fetches]),
                {
                  ..model,
                  parsed: Some(parsed),
                  system_prompt,
                  header_present,
                  log_bytes,
                  status: events_status(parsed),
                },
              )
            }
          }
      }
    }
    WatchSessionsFetched(result) =>
      match result {
        Ok(text) =>
          match parse_session_rows(text) {
            Some(sessions) if sessions != model.sessions => {
              let listed = {
                ..model,
                sessions,
                collapsed_roots: prune_collapsed_roots(
                  model.collapsed_roots,
                  sessions,
                ),
              }
              // The session a link named has started: open it, unless the
              // reader picked something else meanwhile.
              match model.pending_restore_key {
                Some(key) if model.selected is None &&
                  model.dropped is None &&
                  resolve_session_key(sessions, key) is Some(resolved) =>
                  update(emit, Select(resolved), {
                    ..listed,
                    pending_restore_key: None,
                  })
                _ => (@cmd.none, listed)
              }
            }
            _ => (@cmd.none, model)
          }
        Err(_) => (@cmd.none, model)
      }
    FileDropped(name, bytes, file) => {
      let ticket = model.drop_ticket + 1
      (
        @cmd.attempt(
          result => emit(DroppedFileRead(ticket, name, bytes, result)),
          () => file.text(),
        ),
        {
          ..model,
          drop_ticket: ticket,
          loading: true,
          status: "reading \{name}…",
        },
      )
    }
    DroppedFileRead(ticket, name, bytes, result) =>
      // Discard a read that finished after the user moved on — selected a
      // session or dropped a newer file (both advance the ticket).
      if ticket != model.drop_ticket {
        (@cmd.none, model)
      } else {
        match result {
          Ok(text) => (@cmd.none, apply_dropped_file(model, name, bytes, text))
          Err(error) =>
            (
              @cmd.none,
              {
                ..model,
                loading: false,
                status: "failed to read dropped file: \{error}",
              },
            )
        }
      }
    SetMode(mode) => {
      // Keep the hash's v= current, and re-anchor the scroll position: the
      // seq= anchors are shared across views where the event projects, so
      // switching modes stays on (or near) the same event.
      let value = view_mode_value(mode)
      (
        @cmd.batch([
          @cmd.effect(() => set_hash_view(value)),
          @cmd.effect(() => restore_scroll_to_hash_seq()),
        ]),
        { ..model, view_mode: mode, },
      )
    }
    SetArgsView(show_original) =>
      (@cmd.none, { ..model, show_original_args: show_original, })
    ToggleErrorsOnly =>
      (
        @cmd.none,
        {
          ..model,
          errors_only: !model.errors_only,
          escalated_only: false,
          build_errors_only: false,
        },
      )
    // Scroll to the next/previous failed-tool card, cycling. The count is
    // recomputed for the active view, while the browser chooses the target
    // relative to the current viewport so manual scrolling is respected.
    JumpToError(direction) => {
      let count = current_error_count(model)
      if count <= 0 {
        (@cmd.none, model)
      } else {
        (
          @cmd.effect(() => {
            scroll_to_card_from_viewport(".card.tool.error", direction)
          }),
          model,
        )
      }
    }
    ToggleEscalatedOnly =>
      (
        @cmd.none,
        {
          ..model,
          escalated_only: !model.escalated_only,
          errors_only: false,
          build_errors_only: false,
        },
      )
    JumpToEscalated(direction) => {
      let count = current_escalated_count(model)
      if count <= 0 {
        (@cmd.none, model)
      } else {
        (
          @cmd.effect(() => {
            scroll_to_card_from_viewport(".tool-call-escalated", direction)
          }),
          model,
        )
      }
    }
    ToggleBuildErrorsOnly =>
      (
        @cmd.none,
        {
          ..model,
          build_errors_only: !model.build_errors_only,
          errors_only: false,
          escalated_only: false,
        },
      )
    JumpToBuildError(direction) => {
      let count = current_build_error_count(model)
      if count <= 0 {
        (@cmd.none, model)
      } else {
        (
          @cmd.effect(() => {
            // Result cards, not call rows: every build failure has exactly
            // one tagged result card — orphans included — so the jump set
            // matches the count.
            scroll_to_card_from_viewport(".card.build-failed", direction)
          }),
          model,
        )
      }
    }
    UnfoldCurrent => (@cmd.effect(() => unfold_nearest_details()), model)
    SetTheme(theme) =>
      // Apply the theme as a side effect (set `data-theme` on <html>) so the CSS
      // variable blocks take over; the model tracks it for button highlighting.
      (apply_theme(theme), { ..model, theme, })
    ToggleSidebar =>
      (@cmd.none, { ..model, sidebar_visible: !model.sidebar_visible, })
    ToggleRoot(root) =>
      (
        @cmd.none,
        {
          ..model,
          collapsed_roots: toggle_collapsed_root(model.collapsed_roots, root),
        },
      )
  }
}

///|
fn apply_theme(theme : Theme) -> @cmd.Cmd {
  @cmd.effect(() => set_document_theme(theme.value()))
}

///|
fn fetch_text(
  emit : @cmd.Emit[Msg],
  url : String,
  to_msg : (Result[String, Error]) -> Msg,
) -> @cmd.Cmd {
  // A standalone export bakes the API responses into `window.__OPENSEEK_DATA__`,
  // so answer from there when present and skip the network entirely; a normal
  // server build has no such global and falls through to HTTP unchanged.
  if embedded_has(url) {
    emit(to_msg(Ok(embedded_get(url))))
  } else {
    @http.get(url).expect_text(emit.map(to_msg))
  }
}

///|
/// Switch the viewer to a locally dropped session file. Everything comes from
/// the file text itself — the header line carries the identity and system
/// prompt — so no server round-trip is involved.
fn apply_dropped_file(
  model : Model,
  name : String,
  bytes : Int64,
  text : String,
) -> Model {
  let parsed = @viz.parse_events(text)
  let (system_prompt, header_present) = header_info(parsed)
  {
    ..model,
    selected: None,
    dropped: Some(name),
    parsed: Some(parsed),
    system_prompt,
    header_present,
    log_bytes: bytes,
    loading: false,
    status: events_status(parsed),
  }
}

///|
/// The browser opens a dropped file as a navigation unless dragover and drop
/// are both cancelled, so the dragover handler exists purely for
/// `prevent_default`.
fn drop_target_attrs(emit : @cmd.Emit[Msg]) -> @html.Attrs {
  @html.Attrs::build()
  .on_dragover(event => {
    event.prevent_default()
    @cmd.none
  })
  .on_drop(event => read_dropped_file(emit, event))
}

///|
/// Turn a drop event into a `FileDropped` message carrying the first dropped
/// file; `update` tickets and issues the asynchronous read. Non-file drops
/// (text selections, links) are ignored.
fn read_dropped_file(emit : @cmd.Emit[Msg], event : @dom.DragEvent) -> @cmd.Cmd {
  event.prevent_default()
  let transfer = event.get_data_transfer()
  if data_transfer_file_count(transfer) == 0 {
    return @cmd.none
  }
  let name = data_transfer_file_name(transfer, 0)
  let file = data_transfer_file(transfer, 0)
  emit(FileDropped(name, file.get_size().to_int64(), file))
}

///|
/// The status line labels the active view, and while a dropped file is shown
/// the header strip renders it — a session-list outcome arriving late must
/// not clobber the dropped log's summary.
fn list_status(model : Model, message : String) -> String {
  match model.dropped {
    Some(_) => model.status
    None => message
  }
}

///|
/// The id shown for a dropped session: the identity recorded in the file's
/// header when present, the file name for a bare header-less event log.
fn dropped_display_id(name : String, parsed : @session_log.ParsedLog) -> String {
  match parsed.header {
    Some(header) => header.id
    None => name
  }
}

///|
fn install_shortcuts(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    install_error_shortcuts(
      () => scheduler.add(emit(JumpToError(1))),
      () => scheduler.add(emit(JumpToError(-1))),
      () => scheduler.add(emit(UnfoldCurrent)),
    )
  })
}

///|
fn session_url(id : String) -> String {
  "/api/sessions/\{encode_uri_component(id)}"
}

///|
/// Whether this viewer can open one run's timeline.
///
/// A served viewer folds a run on request, so it can offer any run it can see.
/// A standalone export has no server: it can only open a run it baked into
/// itself as an `/api/trajectory` document, which is why the archive decides.
fn trajectory_available(model : Model, root : String) -> Bool {
  !model.standalone || embedded_has(trajectory_url(root))
}

///|
/// The trajectory endpoint for one run root. The root travels as a session id
/// because a run is several files and no single catalog key names it.
fn trajectory_url(
  root : String,
  cursor? : String,
  resolve_root~ : Bool = false,
) -> String {
  let base = "/api/trajectory/\{encode_uri_component(root)}"
  let query : Array[String] = []
  if cursor is Some(token) {
    query.push("cursor=\{encode_uri_component(token)}")
  }
  if resolve_root {
    query.push("resolve_root=1")
  }
  if query.is_empty() {
    base
  } else {
    let joined = query.join("&")
    "\{base}?\{joined}"
  }
}

///|
/// Fetch one run's waterfall. The ticket rides along so a response that
/// arrives after the reader opened another run is dropped.
fn trajectory_fetch(
  emit : @cmd.Emit[Msg],
  root : String,
  ticket : Int32,
  cursor? : String,
  resolve_root~ : Bool = false,
) -> @cmd.Cmd {
  fetch_text(emit, trajectory_url(root, cursor?, resolve_root~), result => {
    TrajectoryFetched(root, ticket, result)
  })
}

///|
/// The instant the run drew the job at, preferring the focused `BackgroundJob`
/// span (or explicit focus start hint) when legacy `bg-1` ids repeat across
/// generations.
fn job_start_hint(
  trace : @trajectory.Trajectory?,
  key : String,
  preferred_span_id? : String,
  start_hint? : Int64,
) -> Int64? {
  match trace {
    Some(trace) => {
      if preferred_span_id is Some(span_id) {
        if trace.spans
          .iter()
          .find_first(span => {
            span.id == span_id &&
            span.kind is BackgroundJob &&
            span_job_keys(span).contains(key)
          })
          is Some(span) {
          return Some(span.started_at_ms)
        }
      }
      if start_hint is Some(ms) {
        return Some(ms)
      }
      match
        trace.spans
        .iter()
        .find_first(span => {
          span.kind is BackgroundJob && span_job_keys(span).contains(key)
        }) {
        Some(span) => Some(span.started_at_ms)
        None => None
      }
    }
    None => start_hint
  }
}

///|
/// Whether this viewer can open a job's log. A served viewer asks the store; a
/// frozen archive could only answer from a baked document, and `--export` bakes
/// session logs and trajectories, not job outputs — so an archive offers no
/// button rather than one that fails on click.
fn job_log_available(model : Model, key : String) -> Bool {
  !model.standalone ||
  embedded_has(job_url(session_id_of_job_key(key), job_id_of_key(key)))
}

///|
fn session_id_of_job_key(key : String) -> String {
  match key.split_once("/") {
    Some(parts) => parts.0.to_owned()
    None => ""
  }
}

///|
/// Read one job's log. The key names the job (`session/job`), so a reply that
/// lands after the reader moved to another run still lands on the right panel.
fn job_log_fetch(
  emit : @cmd.Emit[Msg],
  key : String,
  trace : @trajectory.Trajectory?,
  preferred_span_id? : String,
  start_hint? : Int64,
  cursor? : Int64,
) -> @cmd.Cmd {
  let (session_id, job_id) = match key.split_once("/") {
    Some(parts) => (parts.0.to_owned(), parts.1.to_owned())
    None => (key, "")
  }
  let url = job_url(
    session_id,
    job_id,
    start?=job_start_hint(trace, key, preferred_span_id?, start_hint?),
    cursor?,
  )
  fetch_text(emit, url, result => JobLogFetched(key, cursor, result))
}

///|
/// Resolve a hash `s=` value to a listed row key: exact key first, then by
/// bare session id — subrun chips link `#s=<child session id>`, which the
/// server resolves as a legacy key but a standalone export's embedded data
/// map does not.
fn resolve_session_key(sessions : Array[SessionRow], value : String) -> String? {
  if sessions.any(row => row.key == value) {
    return Some(value)
  }
  sessions.iter().find_first(row => row.id == value).map(row => row.key)
}

///|
/// The child sessions a freshly loaded parent references via subrun briefs,
/// resolved against the current listing: `(child session id, row key)` for
/// each child that actually exists as a sibling session. Ephemeral children
/// (never persisted) resolve to nothing and stay chip-only.
fn subrun_child_refs(
  model : Model,
  parent_key : String,
  parsed : @session_log.ParsedLog,
) -> Array[(String, String)] {
  guard session_row(model, parent_key) is Some(parent_row) else { return [] }
  let session = @viz.session_from_parse(
    parsed,
    id=parent_row.id,
    system_prompt="",
  )
  let child_ids = @viz.subrun_child_ids(session, parent_row.id)
  [
    for child_id in child_ids if resolve_session_key(model.sessions, child_id)
    is Some(key) => (child_id, key)
  ]
}

///|
/// The decoded session key carried by an `s=` hash parameter. Keeping the
/// decoder on this type makes URL parsing a self-contained boundary instead of
/// scattering percent-decoding rules through update branches.
priv struct HashSessionKey(String)

///|
/// A present `s=` parameter whose percent escapes or decoded UTF-8 are invalid.
/// Absence remains `None`; callers catch this error to report malformed links.
priv suberror MalformedHashSessionKey

///|
/// Read the first `s=` parameter from a URL fragment. Subrun links percent-
/// encode UTF-8 bytes, and `+` follows URLSearchParams' spelling for a space.
fn HashSessionKey::from_fragment(
  fragment : StringView,
) -> HashSessionKey? raise MalformedHashSessionKey {
  for parameter in fragment.split("&") {
    if parameter is [.. "s=", .. encoded] {
      return Some(HashSessionKey::decode(encoded))
    }
  }
  None
}

///|
/// The run root carried by a `t=` hash parameter: the trajectory page's own
/// navigation key. Kept apart from `s=` so the two pages cannot fight over one
/// fragment.
priv struct HashTrajectoryRoot(String)

///|
/// Read the first `t=` parameter from a URL fragment.
fn HashTrajectoryRoot::from_fragment(
  fragment : StringView,
) -> HashTrajectoryRoot? {
  match hash_fragment_param(fragment, "t") {
    Some(value) => Some(HashTrajectoryRoot(value))
    None => None
  }
}

///|
fn hash_fragment_param(fragment : StringView, name : String) -> String? {
  let prefix = "\{name}="
  for parameter in fragment.split("&") {
    if parameter.strip_prefix(prefix) is Some(encoded) {
      let decoded = @percent.decode(encoded.replace_all(old="+", new=" ")) catch {
        Malformed(_) => return None
      }
      if decoded.is_empty() {
        return None
      }
      return Some(decoded)
    }
  }
  None
}

///|
fn HashSessionKey::decode(
  encoded : StringView,
) -> HashSessionKey raise MalformedHashSessionKey {
  // A literal `+` is a space; an escaped `%2B` is not, so `+` is replaced
  // before escapes are decoded.
  let value = @percent.decode(encoded.replace_all(old="+", new=" ")) catch {
    Malformed(_) => raise MalformedHashSessionKey
  }
  HashSessionKey(value)
}

///|
fn session_label(model : Model, key : String) -> String {
  match session_row(model, key) {
    Some(row) => row.id
    None => key
  }
}

///|
fn session_row(model : Model, key : String) -> SessionRow? {
  model.sessions.iter().find_first(row => row.key == key)
}

///|
fn events_status(parsed : @session_log.ParsedLog) -> String {
  let base = "\{parsed.events.length()} event(s)"
  if parsed.errors.is_empty() && !parsed.partial_tail {
    base
  } else {
    "\{base} · \{parsed.errors.length()} bad line(s)\{if parsed.partial_tail { " · truncated tail" } else { "" }}"
  }
}

// ---- view ------------------------------------------------------------------

///|
fn view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let main_attrs = if model.trajectory_root is Some(_) {
    @html.Attrs::build().on_scroll(_ => {
      emit(
        TrajectoryScroll(
          read_waterfall_scroll_top(),
          read_waterfall_viewport_h(),
        ),
      )
    })
  } else {
    @html.Attrs::build()
  }
  @html.div(class=app_class(model), attrs=drop_target_attrs(emit)) <| [
    sidebar_pane(emit, model),
    @html.section(class="main", attrs=main_attrs) <| [
      main_toolbar(emit, model),
      main_pane(emit, model),
    ],
  ]
}

///|
/// A base class with `modifier` appended when `on` — the conditional-class
/// idiom shared by the theme/mode/args buttons, the session rows, the app
/// shell, and the error toggle.
fn class_with(base : String, modifier : String, on : Bool) -> String {
  if on {
    "\{base} \{modifier}"
  } else {
    base
  }
}

///|
fn app_class(model : Model) -> String {
  class_with("app", "sidebar-hidden", !model.sidebar_visible)
}

///|
fn sidebar_pane(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  if !model.sidebar_visible {
    return @html.nothing
  }
  @html.aside(class="sidebar") <| [
    @html.div(class="sidebar-head") <| [
      @html.div(class="sidebar-title-row") <| [
        @html.h1(class="brand", "OpenSeek sessions"),
        @html.button(
          class="sidebar-hide-button",
          title="Hide sessions",
          on_click=emit(ToggleSidebar),
        ) <| "Hide",
      ],
      @html.div(class="status") <| model.status,
    ],
    sidebar_list(emit, model),
    theme_toggle(emit, model),
  ]
}

///|
fn main_toolbar(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  if model.sidebar_visible {
    return @html.nothing
  }
  @html.div(class="main-toolbar") <| [
    @html.button(
      class="sidebar-show-button",
      title="Show sessions",
      on_click=emit(ToggleSidebar),
    ) <| "Show sessions",
  ]
}

///|
fn theme_toggle(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="theme-toggle") <| [
    theme_button(emit, model, Light, "Light"),
    theme_button(emit, model, Dark, "Dark"),
    theme_button(emit, model, System, "System"),
  ]
}

///|
fn theme_button(
  emit : @cmd.Emit[Msg],
  model : Model,
  theme : Theme,
  label : String,
) -> @html.Html {
  let classes = class_with("theme-button", "active", model.theme == theme)
  @html.button(class=classes, on_click=emit(SetTheme(theme))) <| label
}

///|
fn sidebar_list(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  if model.sessions.is_empty() {
    return @html.div(class="sidebar-empty") <| "no sessions found"
  }
  let sections : Array[@html.Html] = [
    for group in sidebar_groups(model.sessions) => {
      let rows = sidebar_nested_rows(
        emit,
        model,
        model.sessions.filter(row => {
          session_group(row.root_label, row.is_marker) == group
        }),
      )
      let collapsed = root_collapsed(model, group)
      let display = group_display(group)
      @html.div(class=class_with("session-root", "collapsed", collapsed)) <| [
        @html.button(
          class="session-root-toggle",
          title=if collapsed {
            "Expand \{display}"
          } else {
            "Collapse \{display}"
          },
          on_click=emit(ToggleRoot(group)),
        ) <| [
          @html.span(class="session-root-caret") <| (if collapsed {
            "▸"
          } else {
            "▾"
          }),
          @html.span(class="session-root-name") <| display,
          @html.span(class="session-root-count") <| rows.length().to_string(),
        ],
        if collapsed {
          @html.nothing
        } else {
          @html.ul(class="session-root-sessions") <| rows
        },
      ]
    }
  ]
  @html.div(class="session-list") <| sections
}

///|
/// One group's sidebar rows with subagent children nested under their
/// parent: a `<parent id>-sr-N` row whose parent is listed in the same
/// group renders indented right after it (in listing order) instead of as
/// a stray sibling; an orphan child (parent not listed) stays top-level.
fn sidebar_nested_rows(
  emit : @cmd.Emit[Msg],
  model : Model,
  rows : Array[SessionRow],
) -> Array[@html.Html] {
  let ids = rows.map(row => row.id)
  fn nested_parent(id : String) -> String? {
    match subrun_parent_id(id) {
      Some(parent) if ids.contains(parent) => Some(parent)
      _ => None
    }
  }
  let out : Array[@html.Html] = []
  for row in rows {
    if nested_parent(row.id) is Some(_) {
      continue
    }
    out.push(sidebar_row(emit, model, row))
    for child in rows {
      if nested_parent(child.id) is Some(parent) && parent == row.id {
        out.push(sidebar_row(emit, model, child, child=true))
      }
    }
  }
  out
}

///|
/// The parent session id a subrun child session id derives from
/// (`<parent>-sr-N`), or `None` for every other id.
fn subrun_parent_id(id : String) -> String? {
  lexmatch id {
    (re"^(.|\n)*" as parent) + re"-sr-[0-9]+$" => Some(parent.to_owned())
    _ => None
  }
}

///|
/// Distinct sidebar group keys, in first-seen (most-recently-active) order.
fn sidebar_groups(rows : Array[SessionRow]) -> Array[String] {
  let groups : Array[String] = []
  for row in rows {
    let group = session_group(row.root_label, row.is_marker)
    if !groups.contains(group) {
      groups.push(group)
    }
  }
  groups
}

///|
/// The directory portion of `p` (before the last `/` or `\`), or `""` when
/// `p` has no directory component.
fn parent_dir(p : String) -> String {
  lexmatch p {
    (re"^(.|\n)*" as dir) + re"[/\\][^/\\]*$" => dir.to_owned()
    _ => ""
  }
}

///|
/// The last path segment of `p`.
fn path_basename(p : String) -> String {
  if p =~ (re"^(.|\n)*[/\\]", after~) {
    after.to_owned()
  } else {
    p
  }
}

///|
/// Drop a leading `./` so the default-scan labels (`./app/.openseek`) and an
/// absolute/bare form derive the same group. Without this, `parent_dir` of a
/// `./app` workspace is `.`, which would merge every direct workspace under one
/// `.` heading.
fn strip_dot_prefix(p : String) -> String {
  if p.strip_prefix("./") is Some(p) {
    p.to_owned()
  } else {
    p
  }
}

///|
/// Whether `d` names an actual directory rather than the current one.
fn is_meaningful_dir(d : String) -> Bool {
  !d.is_empty() && d != "."
}

///|
/// The sidebar group key for a session's store path. The server tells us via
/// `is_marker` whether the last path segment is a discovered store marker (e.g.
/// `.openseek`) — only then is it stripped. For a marker store: the container
/// directory holding the workspace (grandparent of the store) so sibling run
/// workspaces (best-of-N copies) cluster under one heading; a workspace directly
/// under the cwd groups by itself; a bare marker under the current directory
/// (`""`). A direct (non-marker) store is its own group, keyed by its full path.
fn session_group(root_label : String, is_marker : Bool) -> String {
  let normalized = strip_dot_prefix(root_label)
  guard is_marker else { return normalized }
  let workspace = parent_dir(normalized)
  let container = parent_dir(workspace)
  if is_meaningful_dir(container) {
    container
  } else if is_meaningful_dir(workspace) {
    workspace
  } else {
    ""
  }
}

///|
/// The per-row label distinguishing sessions within a group: the workspace name
/// when sessions are grouped under a shared container, otherwise the session id.
fn session_row_label(
  root_label : String,
  id : String,
  is_marker : Bool,
) -> String {
  let normalized = strip_dot_prefix(root_label)
  guard is_marker else { return id }
  let workspace = path_basename(parent_dir(normalized))
  if !workspace.is_empty() &&
    session_group(root_label, is_marker) != parent_dir(normalized) {
    workspace
  } else {
    id
  }
}

///|
/// Human heading for a group key (already normalized): the current directory for
/// an empty key, else the path itself.
fn group_display(group : String) -> String {
  if group.is_empty() {
    "current directory"
  } else {
    group
  }
}

///|
fn root_collapsed(model : Model, root : String) -> Bool {
  model.collapsed_roots.contains(root)
}

///|
fn toggle_collapsed_root(roots : Array[String], root : String) -> Array[String] {
  if roots.contains(root) {
    roots.filter(value => value != root)
  } else {
    let next = roots.copy()
    next.push(root)
    next
  }
}

///|
fn prune_collapsed_roots(
  collapsed_roots : Array[String],
  rows : Array[SessionRow],
) -> Array[String] {
  let groups = sidebar_groups(rows)
  collapsed_roots.filter(group => groups.contains(group))
}

///|
fn sidebar_row(
  emit : @cmd.Emit[Msg],
  model : Model,
  row : SessionRow,
  child~ : Bool = false,
) -> @html.Html {
  let selected = model.selected is Some(current) && current == row.key
  let label = if row.first_prompt.is_blank() {
    row.id
  } else {
    row.first_prompt
  }
  let classes = class_with(
    class_with("session-item", "session-child", child),
    "selected",
    selected,
  )
  let root = match row.run_root {
    Some(explicit) => explicit
    None => run_root_of(row.id)
  }
  let needs_resolve = !model.standalone && row.run_root is None
  let timeline_href = if needs_resolve {
    "#t=\{encode_uri_component(root)}&resolve=1"
  } else {
    "#t=\{encode_uri_component(root)}"
  }
  @html.li(class=classes, on_click=emit(Select(row.key))) <| [
    @html.div(class="session-item-label") <| label,
    @html.div(class="session-item-meta") <| [
      @html.span(class="session-item-id") <| session_row_label(
        row.root_label,
        row.id,
        row.is_marker,
      ),
      last_active_view(row.last_active),
      if !child && trajectory_available(model, root) {
        @html.a(
          class="session-timeline-link",
          href=timeline_href,
          title="Open run timeline",
          attrs=@html.Attrs::build().on_click(event => {
            event.stop_propagation()
            @cmd.none
          }),
        ) <| "Timeline"
      } else {
        @html.nothing
      },
    ],
  ]
}

///|
fn main_pane(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  // The trajectory page is its own pane: it shows a whole run, which is not
  // one session's log and outlives the session selection it was opened from.
  if model.trajectory_root is Some(_) {
    return match model.trajectory {
      Some(trace) => trajectory_pane(emit, model, trace)
      None =>
        // The whole-run page has its own empty and error states; the class
        // keeps them apart from the log pane's and from the row spacers that
        // also carry `placeholder`.
        @html.div(class="placeholder trajectory-placeholder") <| (match
          model.trajectory_error {
          Some(error) => error
          None => "Loading trajectory…"
        })
    }
  }
  match (model.dropped, model.selected) {
    (Some(name), _) =>
      match model.parsed {
        Some(parsed) =>
          session_pane(
            emit,
            model,
            parsed,
            id=dropped_display_id(name, parsed),
            root_label=Some("dropped file: \{name}"),
          )
        None => @html.div(class="placeholder") <| model.status
      }
    (None, None) =>
      @html.div(class="placeholder") <| (if model.sidebar_visible {
        "Select a session from the left to view it, or drop an openseek session .jsonl file anywhere in this window."
      } else {
        "Show sessions to select a session, or drop an openseek session .jsonl file anywhere in this window."
      })
    (None, Some(key)) =>
      match model.parsed {
        None =>
          if model.loading {
            @html.div(class="placeholder") <| "Loading \{session_label(model, key)}…"
          } else {
            @html.div(class="placeholder") <| model.status
          }
        Some(parsed) => {
          let row = session_row(model, key)
          let id = match row {
            Some(row) => row.id
            None => key
          }
          session_pane(
            emit,
            model,
            parsed,
            id~,
            root_label=row.map(row => row.root_label),
          )
        }
      }
  }
}

///|
/// Render one parsed session — served or dropped — with the header strip,
/// sticky toolbar, notices, and log.
fn session_pane(
  emit : @cmd.Emit[Msg],
  model : Model,
  parsed : @session_log.ParsedLog,
  id~ : String,
  root_label~ : String?,
) -> @html.Html {
  let session = @viz.session_from_parse(
    parsed,
    id~,
    system_prompt=model.system_prompt,
  )
  let error_count = @viz.rendered_error_count(session, model.view_mode)
  let escalated_count = @viz.rendered_escalated_count(session, model.view_mode)
  let build_error_count = @viz.rendered_build_error_count(
    session,
    model.view_mode,
  )
  let mbtx_present = @viz.session_has_mbtx_activity(session)
  @html.div(class=session_view_class(model)) <| [
    header_strip(model, id, root_label),
    // Pin the view/args toggles and the error bar to the top of the
    // scroll area so they stay reachable while reading a long log.
    @html.div(class="sticky-toolbar") <| [
      mode_row(emit, model, parsed, @viz.step_scrubber(session)),
      // One shared row for every filter bar: stacking them as separate rows
      // grew the sticky toolbar past the fixed scroll offsets the anchor
      // navigation accounts for, which parked jump targets beneath it. Side
      // by side, the common one-or-two-bar case keeps today's height.
      @html.div(class="filter-bars") <| [
        error_bar(emit, model, error_count),
        escalated_bar(emit, model, escalated_count),
        build_error_bar(emit, model, build_error_count, present=mbtx_present),
      ],
    ],
    @viz.render_notices(parsed),
    session_log_view(
      model, session, error_count, escalated_count, build_error_count,
    ),
  ]
}

///|
fn header_strip(model : Model, id : String, root_label : String?) -> @html.Html {
  let prompt_note = if model.header_present {
    "session header loaded"
  } else {
    "no session header (events only)"
  }
  let root_note = match root_label {
    Some(root) => " · \{root}"
    None => ""
  }
  // Only a served session is re-checked; a dropped file is a snapshot.
  let live_note = if model.watch_ms > 0 && model.selected is Some(_) {
    " · live"
  } else {
    ""
  }
  @html.header(class="header-strip") <| [
    @html.div(class="header-id") <| id,
    @html.div(class="header-meta") <| "\{model.status}\{live_note} · \{prompt_note}\{root_note}",
    // A dropped file is a snapshot with no siblings on disk to walk to, so only
    // a session whose run the viewer knows offers the link: a served viewer
    // folds it on request, and a frozen export offers the runs it baked.
    match model.selected {
      Some(key) => {
        let row = session_row(model, key)
        let root = match row.bind(entry => entry.run_root) {
          Some(explicit) => explicit
          None => run_root_of(session_label(model, key))
        }
        let needs_resolve = !model.standalone &&
          row.bind(entry => entry.run_root) is None
        let href = if needs_resolve {
          "#t=\{encode_uri_component(root)}&resolve=1"
        } else {
          "#t=\{encode_uri_component(root)}"
        }
        if trajectory_available(model, root) {
          @html.a(
            class="trajectory-open",
            href~,
            title="Show this run's timeline: every session, turn and step on one axis",
          ) <| "Trajectory"
        } else {
          @html.nothing
        }
      }
      None => @html.nothing
    },
  ]
}

///|
fn mode_toggle(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="mode-toggle") <| [
    mode_button(emit, model, RawLog, "Raw log"),
    mode_button(emit, model, ModelView, "Model view"),
  ]
}

///|
fn mode_row(
  emit : @cmd.Emit[Msg],
  model : Model,
  parsed : @session_log.ParsedLog,
  scrubber : @html.Html,
) -> @html.Html {
  @html.div(class="mode-row") <| [
    @html.div(class="mode-cluster") <| [
      mode_toggle(emit, model),
      args_toggle(emit, model),
    ],
    scrubber,
    session_metadata(model, parsed),
  ]
}

///|
/// Toggle between the human-friendly tool-argument rendering (values verbatim, no
/// JSON quoting) and the original pretty-printed JSON kept for debugging. Both are
/// always in the DOM; this only flips which one the stylesheet shows.
fn args_toggle(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="mode-toggle args-toggle") <| [
    @html.span(class="args-toggle-label") <| "Tool args",
    args_button(emit, model, false, "Rendered"),
    args_button(emit, model, true, "Original"),
  ]
}

///|
fn args_button(
  emit : @cmd.Emit[Msg],
  model : Model,
  show_original : Bool,
  label : String,
) -> @html.Html {
  let classes = class_with(
    "mode-button",
    "active",
    model.show_original_args == show_original,
  )
  @html.button(class=classes, on_click=emit(SetArgsView(show_original))) <| label
}

///|
fn mode_button(
  emit : @cmd.Emit[Msg],
  model : Model,
  mode : @viz.ViewMode,
  label : String,
) -> @html.Html {
  let classes = class_with("mode-button", "active", model.view_mode == mode)
  @html.button(class=classes, on_click=emit(SetMode(mode))) <| label
}

///|
fn session_metadata(
  model : Model,
  parsed : @session_log.ParsedLog,
) -> @html.Html {
  let steps = agent_step_count(parsed)
  @html.div(class="session-metadata") <| [
    @html.span("log \{format_log_size(model.log_bytes)}"),
    @html.span("\{steps} step\{plural_s(steps)}"),
    @html.span("runtime \{runtime_label(parsed)}"),
    @html.span("ended \{end_time_label(parsed)}"),
  ]
}

///|
fn agent_step_count(parsed : @session_log.ParsedLog) -> Int32 {
  parsed.events.count_if(event => event.is_agent_step())
}

///|
fn runtime_label(parsed : @session_log.ParsedLog) -> String {
  match running_ms(parsed) {
    Some(milliseconds) => format_span_total_seconds(milliseconds)
    None => "n/a"
  }
}

///|
fn running_ms(parsed : @session_log.ParsedLog) -> Int64? {
  match stamp_range(parsed) {
    // A torn log can stamp backwards; show no span rather than a negative one.
    Some((first, last)) if last >= first => Some(last - first)
    _ => None
  }
}

///|
/// The first and last positive wall-clock stamps in the log (unix ms), in file
/// order, or `None` when no event carries one.
fn stamp_range(parsed : @session_log.ParsedLog) -> (Int64, Int64)? {
  let mut first = 0L
  let mut last = 0L
  for event in parsed.events {
    let stamp = event.unix_ms()
    if stamp > 0 {
      if first == 0L {
        first = stamp
      }
      last = stamp
    }
  }
  if first > 0L {
    Some((first, last))
  } else {
    None
  }
}

///|
fn end_time_label(parsed : @session_log.ParsedLog) -> String {
  match last_event_ms(parsed) {
    Some(milliseconds) => absolute_time_label(milliseconds)
    None => "n/a"
  }
}

///|
fn last_event_ms(parsed : @session_log.ParsedLog) -> Int64? {
  stamp_range(parsed).map(range => range.1)
}

///|
fn format_span_total_seconds(span_ms : Int64) -> String {
  let tenths = span_ms / 100L
  "\{tenths / 10L}.\{tenths % 10L}s"
}

///|
fn last_active_label(last_active : Int64?) -> String {
  match last_active {
    Some(seconds) => absolute_time_label(seconds * 1000L)
    None => ""
  }
}

///|
fn absolute_time_label(milliseconds : Int64) -> String {
  let d = milliseconds.to_double()
  let stamp = format_unix_ms_local(d)
  if stamp.is_empty() {
    ""
  } else {
    "\{stamp} \{local_tz_label(d)}"
  }
}

///|
fn last_active_view(last_active : Int64?) -> @html.Html {
  let label = last_active_label(last_active)
  if label.is_empty() {
    @html.nothing
  } else {
    @html.span(class="session-item-time") <| label
  }
}

///|
fn format_log_size(bytes : Int64) -> String {
  if bytes < 1024L {
    "\{bytes} B"
  } else if bytes < 1048576L {
    format_scaled_size(bytes, 1024L, "KiB")
  } else {
    format_scaled_size(bytes, 1048576L, "MiB")
  }
}

///|
fn format_scaled_size(bytes : Int64, unit : Int64, suffix : String) -> String {
  let tenths = bytes * 10L / unit
  "\{tenths / 10L}.\{tenths % 10L} \{suffix}"
}

///|
/// Add the active log-filter class, plus `show-original` when raw tool-call JSON
/// should replace the friendly argument rendering.
fn session_view_class(model : Model) -> String {
  let with_errors = class_with("session-view", "errors-only", model.errors_only)
  let with_escalated = class_with(
    with_errors,
    "escalated-only",
    model.escalated_only,
  )
  let with_build = class_with(
    with_escalated,
    "build-errors-only",
    model.build_errors_only,
  )
  class_with(with_build, "show-original", model.show_original_args)
}

///|
/// The shape the three "find X" toolbars share: an optional count chip, a
/// filter toggle that reads `<label>: on` while active, and prev/next jumps.
/// `kind` is the CSS prefix the three sets of rules are already keyed on
/// (`error`, `escalated`, `build-error`). Each caller keeps its own
/// visibility test, because those genuinely differ.
fn filter_bar(
  emit : @cmd.Emit[Msg],
  count : Int32,
  kind~ : String,
  active~ : Bool,
  count_label~ : String,
  toggle_title~ : String,
  toggle_label~ : String,
  toggle~ : Msg,
  jump~ : (Int32) -> Msg,
  jump_noun~ : String,
) -> @html.Html {
  let children : Array[@html.Html] = [
    ..if count > 0 {
      [@html.span(class="\{kind}-count") <| count_label]
    },
    @html.button(
      class=class_with("\{kind}-toggle", "active", active),
      title=toggle_title,
      on_click=emit(toggle),
    ) <| (if active { "\{toggle_label}: on" } else { toggle_label }),
    // Jumps only make sense when there is something to jump to.
    ..if count > 0 {
      [
        @html.button(
          class="\{kind}-jump",
          title="Scroll to the previous \{jump_noun}",
          on_click=emit(jump(-1)),
        ) <| "↑ prev",
        @html.button(
          class="\{kind}-jump",
          title="Scroll to the next \{jump_noun}",
          on_click=emit(jump(1)),
        ) <| "↓ next",
      ]
    },
  ]
  @html.div(class="\{kind}-bar") <| children
}

///|
/// The "find failures" toolbar: a count, an errors-only filter toggle, and
/// prev/next jumps. Hidden when the view has no failures AND the filter is off,
/// so a clean session shows no chrome — but if the filter is on it stays visible
/// even at zero failures, otherwise "Errors only" could hide the whole log with
/// no way to switch it back off.
fn error_bar(emit : @cmd.Emit[Msg], model : Model, count : Int32) -> @html.Html {
  if count == 0 && !model.errors_only {
    return @html.nothing
  }
  filter_bar(
    emit,
    count,
    kind="error",
    active=model.errors_only,
    count_label="🚩 \{count} tool error\{plural_s(count)}",
    toggle_title="Show only failed tool results",
    toggle_label="Errors only",
    toggle=ToggleErrorsOnly,
    jump=n => JumpToError(n),
    jump_noun="failure",
  )
}

///|
/// Escalated-call counterpart of `error_bar`: a count, filter toggle, and
/// viewport-relative prev/next jumps. It stays visible at zero while active so
/// switching views can never strand the user in an apparently empty pane.
fn escalated_bar(
  emit : @cmd.Emit[Msg],
  model : Model,
  count : Int32,
) -> @html.Html {
  if count == 0 && !model.escalated_only {
    return @html.nothing
  }
  filter_bar(
    emit,
    count,
    kind="escalated",
    active=model.escalated_only,
    count_label="🔓 \{count} escalated tool call\{plural_s(count)}",
    toggle_title="Show only tool calls with escalated: true and their results",
    toggle_label="Escalated only",
    toggle=ToggleEscalatedOnly,
    jump=n => JumpToEscalated(n),
    jump_noun="escalated tool call",
  )
}

///|
/// Build-error counterpart of `escalated_bar`: a count of mbtx BUILD-stage
/// failures (the staged engine's `mbtx build` brief), a filter toggle,
/// and viewport-relative prev/next jumps — the way to find compile errors in
/// a long log without reading it. Unlike its siblings it shows whenever the
/// session has ANY mbtx activity (`present`), not only at nonzero count:
/// hidden-at-zero chrome made the control undiscoverable on exactly the
/// sessions a user would reach for it in. It still stays visible at zero
/// while active so the filter can always be switched back off, and a session
/// with no mbtx at all keeps a clean toolbar.
fn build_error_bar(
  emit : @cmd.Emit[Msg],
  model : Model,
  count : Int32,
  present~ : Bool,
) -> @html.Html {
  if !present && count == 0 && !model.build_errors_only {
    return @html.nothing
  }
  filter_bar(
    emit,
    count,
    kind="build-error",
    active=model.build_errors_only,
    count_label="🔨 \{count} build error\{plural_s(count)}",
    toggle_title="Show only mbtx calls whose build failed, with their results",
    toggle_label="Build errors only",
    toggle=ToggleBuildErrorsOnly,
    jump=n => JumpToBuildError(n),
    jump_noun="build error",
  )
}

///|
/// The log, or a hint when the errors-only filter would hide everything (so the
/// pane never looks empty/broken when a clean view is filtered).
fn session_log_view(
  model : Model,
  session : @agent_session.Session,
  error_count : Int32,
  escalated_count : Int32,
  build_error_count : Int32,
) -> @html.Html {
  if model.errors_only && error_count == 0 {
    @html.div(class="errors-only-empty") <| "No failed tool results in this view."
  } else if model.escalated_only && escalated_count == 0 {
    @html.div(class="escalated-only-empty") <| "No escalated tool calls in this view."
  } else if model.build_errors_only && build_error_count == 0 {
    @html.div(class="build-errors-only-empty") <| "No mbtx build errors in this view."
  } else {
    let tz_offset_ms = local_tz_offset_ms(
      model.parsed
      .bind(parsed => parsed.events.last())
      .map(event => event.unix_ms())
      .unwrap_or(0L)
      .to_double(),
    ).to_int64()
    @viz.render_session(
      session,
      model.view_mode,
      subrun_children=model.subrun_children,
      tz_offset_ms~,
    )
  }
}

///|
/// Number of failures the active view will draw, recomputed from the loaded
/// log — served or dropped; the session id plays no part in the count.
/// Returns 0 when nothing is loaded.
fn current_error_count(model : Model) -> Int32 {
  guard model.parsed is Some(parsed) else { return 0 }
  let session = @viz.session_from_parse(
    parsed,
    id="",
    system_prompt=model.system_prompt,
  )
  @viz.rendered_error_count(session, model.view_mode)
}

///|
/// Number of explicitly escalated calls the active projection will render.
fn current_escalated_count(model : Model) -> Int32 {
  guard model.parsed is Some(parsed) else { return 0 }
  let session = @viz.session_from_parse(
    parsed,
    id="",
    system_prompt=model.system_prompt,
  )
  @viz.rendered_escalated_count(session, model.view_mode)
}

///|
fn current_build_error_count(model : Model) -> Int32 {
  guard model.parsed is Some(parsed) else { return 0 }
  let session = @viz.session_from_parse(
    parsed,
    id="",
    system_prompt=model.system_prompt,
  )
  @viz.rendered_build_error_count(session, model.view_mode)
}

///|
fn plural_s(n : Int32) -> String {
  if n == 1 {
    ""
  } else {
    "s"
  }
}

// ---- JSON helpers ----------------------------------------------------------

///|
/// Decode the `/api/sessions` listing. Returns `None` when the body is not a
/// JSON array (e.g. a server error body that `rabbita/http` still delivers as
/// `Ok`), so the caller can surface the failure instead of conflating it with a
/// genuinely empty `[]`.
fn parse_session_rows(text : String) -> Array[SessionRow]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Array(items) else { return None }
  Some(items.filter_map(session_row_of))
}

///|
fn session_row_of(json : Json) -> SessionRow? {
  guard json
    is {
      "id": String(id),
      "first_prompt"? : Some(String(first_prompt))
      | (_ with first_prompt = ""),
      ..
    } else {
    return None
  }
  let key = match json {
    { "key": String(value), .. } => value
    _ => id
  }
  let root_label = match json {
    { "root_label": String(value), .. } => value
    { "root"? : Some(String(value)) | (_ with value = ""), .. } => value
    _ => ""
  }
  let run_root = match json {
    { "run_root": String(value), .. } if !value.is_empty() => Some(value)
    _ => None
  }
  let last_active = match json {
    { "last_active": Number(value, ..), .. } => Some(value.to_int64())
    _ => None
  }
  let is_marker = json is { "is_marker": true, .. }
  Some({ key, id, root_label, run_root, last_active, is_marker, first_prompt, })
}

///|
/// Decode the `/api/sessions/<id>` envelope into a `LoadOutcome`. `events` is
/// the raw session-file text; the header record on its first line carries the
/// system prompt, lifted out so the viewer can label the header strip and seed
/// the model view.
fn parse_load(text : String) -> LoadOutcome {
  let json = @json.parse(text) catch { _ => return Malformed }
  match json {
    { "found": false, .. } => NotFound
    { "found": true, "unchanged": True, .. } => Unchanged
    { "found": true, "events": String(events_text), .. } => {
      let parsed = @viz.parse_events(events_text)
      let (system_prompt, header_present) = header_info(parsed)
      let log_bytes = match json {
        { "events_bytes": Number(value, ..), .. } => value.to_int64()
        _ => events_text.length().to_int64()
      }
      Loaded(parsed, system_prompt, header_present, log_bytes)
    }
    _ => Malformed
  }
}

///|
test "parse_load reads a watch reply for an unchanged log" {
  assert_true(
    parse_load("{\"found\":true,\"unchanged\":true,\"events_bytes\":77}")
    is Unchanged,
  )
  // Without the marker, a reply lacking `events` is still malformed.
  assert_true(parse_load("{\"found\":true,\"events_bytes\":77}") is Malformed)
}

///|
/// Lift the header line's identity out of a parsed log:
/// `(system_prompt, header_present)`. Shared by the served and dropped-file
/// paths so both label the header strip and seed the model view the same way.
fn header_info(parsed : @session_log.ParsedLog) -> (String, Bool) {
  match parsed.header {
    Some(header) => (header.system_prompt, true)
    None => ("", false)
  }
}

///|
test "parse_load lifts the system prompt from the header line" {
  let text =
    #|{"found":true,"events":"{\"version\":1,\"id\":\"demo\",\"system_prompt\":\"SYS\"}\n{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\n","events_bytes":77}
  guard parse_load(text)
    is Loaded(parsed, system_prompt, header_present, log_bytes) else {
    fail("expected Loaded")
  }
  inspect(parsed.events.length(), content="1")
  inspect(system_prompt, content="SYS")
  inspect(header_present, content="true")
  inspect(log_bytes, content="77")
}

///|
test "parse_load treats a header-less file as events-only" {
  let text =
    #|{"found":true,"events":""}
  guard parse_load(text) is Loaded(_, system_prompt, header_present, log_bytes) else {
    fail("expected Loaded")
  }
  inspect(system_prompt, content="")
  inspect(header_present, content="false")
  inspect(log_bytes, content="0")
}

///|
test "session metadata counts steps and total runtime" {
  let text =
    #|{"found":true,"events":"{\"sequence\":1,\"ts\":100000,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\n{\"sequence\":2,\"ts\":101500,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"\",\"tool_calls\":[]}}}\n{\"sequence\":3,\"ts\":170300,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"done\"}}}\n","events_bytes":307}
  guard parse_load(text) is Loaded(parsed, _, _, log_bytes) else {
    fail("expected Loaded")
  }
  inspect(format_log_size(log_bytes), content="307 B")
  inspect(agent_step_count(parsed), content="1")
  inspect(runtime_label(parsed), content="70.3s")
  let expected_end = "\{format_unix_ms_local(170300.0)} \{local_tz_label(170300.0)}"
  assert_eq(end_time_label(parsed), expected_end)
}

///|
test "absolute time labels format local timestamps with timezone" {
  let expected_zero = "\{format_unix_ms_local(0.0)} \{local_tz_label(0.0)}"
  assert_eq(absolute_time_label(0L), expected_zero)
  assert_eq(last_active_label(Some(0L)), expected_zero)
  inspect(last_active_label(None), content="")
}

///|
test "log size formats larger byte counts" {
  inspect(format_log_size(554702L), content="541.7 KiB")
  inspect(format_log_size(2097152L), content="2.0 MiB")
}

///|
test "apply_dropped_file switches to local-file mode with the header lifted" {
  let text =
    #|{"version":1,"id":"demo","system_prompt":"SYS"}
    #|{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":"hi"}}}
    #|
  let selected = { ..init_model(), selected: Some("0|remote"), loading: true, }
  let model = apply_dropped_file(selected, "run.jsonl", 123L, text)
  debug_inspect(model.selected, content="None")
  debug_inspect(model.dropped, content="Some(\"run.jsonl\")")
  inspect(model.system_prompt, content="SYS")
  inspect(model.header_present, content="true")
  inspect(model.log_bytes, content="123")
  inspect(model.loading, content="false")
  guard model.parsed is Some(parsed) else { fail("expected parsed log") }
  inspect(parsed.events.length(), content="1")
}

///|
test "apply_dropped_file tolerates a header-less event log" {
  let text =
    #|{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":"hi"}}}
    #|
  let model = apply_dropped_file(init_model(), "bare.jsonl", 75L, text)
  inspect(model.system_prompt, content="")
  inspect(model.header_present, content="false")
  guard model.parsed is Some(parsed) else { fail("expected parsed log") }
  inspect(parsed.events.length(), content="1")
}

///|
test "dropped display id prefers the header identity over the file name" {
  let with_header = @viz.parse_events(
    (
      #|{"version":1,"id":"cli-123","system_prompt":"SYS"}
      #|
    ),
  )
  inspect(dropped_display_id("run.jsonl", with_header), content="cli-123")
  let bare = @viz.parse_events("")
  inspect(dropped_display_id("run.jsonl", bare), content="run.jsonl")
}

///|
test "parse_load distinguishes not-found from malformed" {
  guard parse_load("{\"found\":false}") is NotFound else {
    fail("expected NotFound")
  }
  guard parse_load("not json") is Malformed else { fail("expected Malformed") }
  guard parse_load("{\"events\":\"x\"}") is Malformed else {
    fail("expected Malformed when found is missing")
  }
}

///|
test "parse_session_rows reads the listing, skipping malformed rows" {
  let text =
    #|[{"key":"0|a","id":"a","root_label":"app/.openseek","last_active":1,"first_prompt":"hello"},{"first_prompt":"no id"},{"id":"b","root":"lib/.openseek","first_prompt":""}]
  guard parse_session_rows(text) is Some(rows) else { fail("expected Some") }
  inspect(rows.length(), content="2")
  inspect(rows[0].key, content="0|a")
  inspect(rows[0].id, content="a")
  inspect(rows[0].root_label, content="app/.openseek")
  inspect(rows[0].first_prompt, content="hello")
  debug_inspect(rows[0].last_active, content="Some(1)")
  inspect(rows[1].key, content="b")
  inspect(rows[1].id, content="b")
  inspect(rows[1].root_label, content="lib/.openseek")
  debug_inspect(rows[1].last_active, content="None")
}

///|
test "parse_session_rows distinguishes empty list from a non-array body" {
  guard parse_session_rows("[]") is Some(empty) else {
    fail("expected Some([])")
  }
  inspect(empty.length(), content="0")
  guard parse_session_rows("oops 500") is None else {
    fail("expected None for a non-JSON body")
  }
  guard parse_session_rows("{\"error\":\"x\"}") is None else {
    fail("expected None for a non-array body")
  }
}

///|
test "session_url percent-encodes the id" {
  inspect(session_url("0|a b/c"), content="/api/sessions/0%7Ca%20b%2Fc")
}

///|
test "session grouping derives container, row label, and heading" {
  // A nested run workspace (marker store): grouped by container, labelled by
  // workspace name.
  inspect(session_group("/tmp/ab/A-1/.openseek", true), content="/tmp/ab")
  inspect(
    session_row_label("/tmp/ab/A-1/.openseek", "run", true),
    content="A-1",
  )
  inspect(group_display("/tmp/ab"), content="/tmp/ab")
  // A workspace directly under cwd groups by itself, labelled by id — and the
  // default-scan "./" prefix normalizes to the same key as the bare form.
  inspect(session_group("./app/.openseek", true), content="app")
  inspect(session_group("app/.openseek", true), content="app")
  inspect(session_row_label("./app/.openseek", "c", true), content="c")
  // A bare cwd store: the current-directory group, labelled by id.
  inspect(session_group("./.openseek", true), content="")
  inspect(session_group(".openseek", true), content="")
  inspect(session_row_label(".openseek", "cli-1", true), content="cli-1")
  inspect(group_display(""), content="current directory")
  // Nested "./"-prefixed roots cluster by their normalized container.
  inspect(
    session_group("./.repos/toml_run_1/.openseek", true),
    content=".repos",
  )
  inspect(
    session_row_label("./.repos/toml_run_1/.openseek", "run", true),
    content="toml_run_1",
  )
  // A direct store (is_marker=false) is its own group, labelled by id — even a
  // hidden one is NOT stripped, so unrelated direct stores never merge.
  inspect(
    session_group("/tmp/openseek-sessions", false),
    content="/tmp/openseek-sessions",
  )
  inspect(
    session_row_label("/tmp/openseek-sessions", "cli-1", false),
    content="cli-1",
  )
  inspect(
    session_group("/tmp/.my-sessions", false),
    content="/tmp/.my-sessions",
  )
  // A non-hidden marker (e.g. --session-root-name sessions) still groups by
  // container when the server flags it as a marker.
  inspect(session_group("runs/A-1/sessions", true), content="runs")
  inspect(session_row_label("runs/A-1/sessions", "x", true), content="A-1")
}

///|
test "app class tracks sidebar visibility" {
  let visible = { ..init_model(), sidebar_visible: true, }
  let hidden = { ..init_model(), sidebar_visible: false, }
  inspect(app_class(visible), content="app")
  inspect(app_class(hidden), content="app sidebar-hidden")
}

///|
test "theme values map to the data-theme attribute" {
  inspect(Theme::value(Light), content="light")
  inspect(Theme::value(Dark), content="dark")
  inspect(Theme::value(System), content="system")
  // The viewer follows the OS by default.
  assert_true(init_model().theme == System)
}

///|
test "standalone exports default raw while the live viewer defaults model" {
  assert_true(initial_view_mode(true) == RawLog)
  assert_true(initial_view_mode(false) == ModelView)
  assert_true(init_model().view_mode == ModelView)
}

///|
/// The hash's `v=` overrides the standalone/live view-mode defaults on
/// restore; anything else falls through to them.
test "the hash view mode wins over the defaults" {
  assert_true(restored_view_mode(Some("raw"), false) == RawLog)
  assert_true(restored_view_mode(Some("model"), true) == ModelView)
  assert_true(restored_view_mode(None, true) == RawLog)
  assert_true(restored_view_mode(None, false) == ModelView)
  assert_true(restored_view_mode(Some(""), true) == RawLog)
  assert_true(restored_view_mode(Some(""), false) == ModelView)
  assert_true(restored_view_mode(Some("nonsense"), false) == ModelView)
  inspect(view_mode_value(RawLog), content="raw")
  inspect(view_mode_value(ModelView), content="model")
}

///|
test "session view class includes the build-error filter" {
  let filtered = { ..init_model(), build_errors_only: true, }
  inspect(
    session_view_class(filtered),
    content="session-view build-errors-only",
  )
}

///|
test "session view class includes the escalated filter" {
  let filtered = {
    ..init_model(),
    escalated_only: true,
    show_original_args: true,
  }
  inspect(
    session_view_class(filtered),
    content="session-view escalated-only show-original",
  )
}

///|
/// The root session a run hangs from: `run-sr-1-sr-2` is `run`. A session id
/// that merely contains `-sr-` (with a non-numeric tail) is its own root.
fn run_root_of(id : String) -> String {
  let mut current = id.to_string()
  while @trajectory.parent_session_of(current) is Some(parent) {
    current = parent
  }
  current
}
