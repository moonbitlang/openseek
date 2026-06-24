///|
/// One row of the `/api/sessions` listing shown in the sidebar. The server
/// already returns rows most-recently-active first; the row keeps `last_active`
/// so the sidebar can show when an experiment last wrote to disk.
struct SessionRow {
  key : String
  id : String
  root_label : String
  last_active : Int64?
  // Whether the server discovered this root as a marker store (a `.openseek`-like
  // directory) rather than a direct `--session-root` store. Drives whether the
  // sidebar strips the last path segment when grouping. Absent → `false`.
  is_marker : Bool
  first_prompt : String
}

///|
/// The whole viewer state. The current session is kept as the parsed log plus a
/// system prompt fetched from `session.json`; the typed `Session` and its model
/// projection are rebuilt in `view` so the two view modes always agree with the
/// bytes on disk.
struct Model {
  sessions : Array[SessionRow]
  selected : String?
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
  // Tool-call arguments rendering: the human-friendly form (values shown verbatim,
  // no JSON quoting) by default, or the original pretty-printed JSON for debugging.
  show_original_args : Bool
}

///|
/// Colour theme. `Light` is the default; `System` follows the OS via a CSS
/// `prefers-color-scheme` media query (so it tracks live OS changes without any
/// listener). The choice is applied by setting `data-theme` on `<html>`.
enum Theme {
  Light
  Dark
  System
} derive(Eq)

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
  SetMode(@viz.ViewMode)
  SetArgsView(Bool)
  SetTheme(Theme)
  ToggleSidebar
  ToggleRoot(String)
  ToggleErrorsOnly
  JumpToError(Int)
  UnfoldCurrent
}

///|
/// Outcome of decoding the `/api/sessions/<id>` envelope. `rabbita/http` reports
/// any completed response as `Ok`, so absence and malformed payloads are
/// distinguished here from the body, not the HTTP status.
enum LoadOutcome {
  Loaded(@session_log.ParsedLog, String, Bool, Int64)
  NotFound
  Malformed
}

///|
fn init_model() -> Model {
  {
    sessions: [],
    selected: None,
    parsed: None,
    system_prompt: "",
    header_present: false,
    log_bytes: 0L,
    view_mode: ModelView,
    theme: Light,
    sidebar_visible: true,
    collapsed_roots: [],
    loading: false,
    status: "loading sessions…",
    errors_only: false,
    show_original_args: false,
  }
}

// ---- update ----------------------------------------------------------------

///|
fn update(emit : @cmd.Emit[Msg], msg : Msg, model : Model) -> (@cmd.Cmd, Model) {
  match msg {
    SessionsFetched(Ok(text)) =>
      match parse_session_rows(text) {
        Some(sessions) =>
          (
            @cmd.none,
            {
              ..model,
              sessions,
              collapsed_roots: prune_collapsed_roots(
                model.collapsed_roots,
                sessions,
              ),
              status: "\{sessions.length()} session(s)",
            },
          )
        None =>
          (@cmd.none, { ..model, status: "could not read the session list" })
      }
    SessionsFetched(Err(error)) =>
      (@cmd.none, { ..model, status: "failed to list sessions: \{error}" })
    Select(key) => {
      let label = session_label(model, key)
      let command = fetch_text(emit, session_url(key), result => {
        SessionFetched(key, result)
      })
      (
        command,
        {
          ..model,
          selected: Some(key),
          parsed: None,
          system_prompt: "",
          header_present: false,
          log_bytes: 0L,
          loading: true,
          status: "loading \{label}…",
        },
      )
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
              { ..model, loading: false, status: "request failed: \{error}" },
            )
          Ok(text) =>
            match parse_load(text) {
              Loaded(parsed, system_prompt, header_present, log_bytes) =>
                (
                  @cmd.none,
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
              Malformed =>
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
    SetMode(mode) => (@cmd.none, { ..model, view_mode: mode })
    SetArgsView(show_original) =>
      (@cmd.none, { ..model, show_original_args: show_original })
    ToggleErrorsOnly =>
      (@cmd.none, { ..model, errors_only: !model.errors_only })
    // Scroll to the next/previous failed-tool card, cycling. The count is
    // recomputed for the active view, while the browser chooses the target
    // relative to the current viewport so manual scrolling is respected.
    JumpToError(direction) => {
      let count = current_error_count(model)
      if count <= 0 {
        (@cmd.none, model)
      } else {
        (@cmd.effect(() => scroll_to_error_from_viewport(direction)), model)
      }
    }
    UnfoldCurrent => (@cmd.effect(() => unfold_nearest_details()), model)
    SetTheme(theme) =>
      // Apply the theme as a side effect (set `data-theme` on <html>) so the CSS
      // variable blocks take over; the model tracks it for button highlighting.
      (apply_theme(theme), { ..model, theme, })
    ToggleSidebar =>
      (@cmd.none, { ..model, sidebar_visible: !model.sidebar_visible })
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
/// Set `data-theme` on the document root. `light`/`dark` pick a fixed palette;
/// `system` defers to the OS via the stylesheet's `prefers-color-scheme` query.
extern "js" fn set_document_theme(theme : String) -> Unit = "(t) => document.documentElement.setAttribute('data-theme', t)"

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
  @http.get(url).expect_text(emit.map(to_msg))
}

///|
/// Percent-encode the id so session ids containing URL-reserved characters
/// (spaces, `?`, `#`) reach the server intact; it percent-decodes the segment.
extern "js" fn encode_uri_component(value : String) -> String = "encodeURIComponent"

///|
extern "js" fn format_unix_ms_utc(milliseconds : Double) -> String =
  #|(milliseconds) => {
  #|  const date = new Date(milliseconds);
  #|  if (!Number.isFinite(date.getTime())) return "";
  #|  return date.toISOString().slice(0, 16).replace("T", " ") + " UTC";
  #|}

///|
/// Scroll to the next/previous failed-tool card relative to the viewport's
/// centre, not an internal cursor, so manual scrolling changes the jump origin.
extern "js" fn scroll_to_error_from_viewport(direction : Int) -> Unit =
  #|(direction) => {
  #|  const els = Array.from(document.querySelectorAll('.card.tool.error'))
  #|    .filter((el) => el.getClientRects().length > 0);
  #|  if (!els.length) return;
  #|  const anchor = window.innerHeight / 2;
  #|  const epsilon = 1;
  #|  let index = -1;
  #|  if (direction >= 0) {
  #|    index = els.findIndex((el) => el.getBoundingClientRect().top > anchor + epsilon);
  #|    if (index < 0) index = 0;
  #|  } else {
  #|    for (let i = els.length - 1; i >= 0; i--) {
  #|      if (els[i].getBoundingClientRect().bottom < anchor - epsilon) {
  #|        index = i;
  #|        break;
  #|      }
  #|    }
  #|    if (index < 0) index = els.length - 1;
  #|  }
  #|  els[index].scrollIntoView({ behavior: 'smooth', block: 'center' });
  #|}

///|
/// Open the nearest folded details block in the viewport: failed tool cards,
/// folded tool-call args, reasoning blocks, or a user-collapsed turn.
extern "js" fn unfold_nearest_details() -> Unit =
  #|() => {
  #|  const candidates = Array.from(document.querySelectorAll(
  #|    'details.card:not([open]), details.tool-call:not([open]), details.reasoning:not([open]), details.turn:not([open])'
  #|  )).filter((el) => el.getClientRects().length > 0);
  #|  if (!candidates.length) return;
  #|  const anchor = window.innerHeight / 2;
  #|  const visible = candidates.filter((el) => {
  #|    const rect = el.getBoundingClientRect();
  #|    return rect.bottom >= 0 && rect.top <= window.innerHeight;
  #|  });
  #|  const pool = visible.length ? visible : candidates;
  #|  let best = pool[0];
  #|  let bestDistance = Infinity;
  #|  for (const el of pool) {
  #|    const rect = el.getBoundingClientRect();
  #|    const center = rect.top + rect.height / 2;
  #|    const distance = Math.abs(center - anchor);
  #|    if (distance < bestDistance) {
  #|      best = el;
  #|      bestDistance = distance;
  #|    }
  #|  }
  #|  best.open = true;
  #|  best.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  #|}

///|
/// Install plain `n` / `p` failure jumps and `u` unfold. Text-entry targets and
/// modified keys are left alone.
extern "js" fn install_error_shortcuts(
  next : () -> Unit,
  previous : () -> Unit,
  unfold : () -> Unit,
) -> Unit =
  #|(next, previous, unfold) => {
  #|  document.addEventListener('keydown', (event) => {
  #|    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return;
  #|    const target = event.target;
  #|    const tag = target && target.tagName ? target.tagName.toLowerCase() : '';
  #|    if (tag === 'input' || tag === 'textarea' || tag === 'select' || (target && target.isContentEditable)) return;
  #|    const key = event.key.toLowerCase();
  #|    if (key === 'n') {
  #|      event.preventDefault();
  #|      next();
  #|    } else if (key === 'p') {
  #|      event.preventDefault();
  #|      previous();
  #|    } else if (key === 'u') {
  #|      event.preventDefault();
  #|      unfold();
  #|    }
  #|  });
  #|}

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
fn session_label(model : Model, key : String) -> String {
  match session_row(model, key) {
    Some(row) => row.id
    None => key
  }
}

///|
fn session_row(model : Model, key : String) -> SessionRow? {
  for row in model.sessions {
    if row.key == key {
      return Some(row)
    }
  }
  None
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
  @html.div(class=app_class(model)) <| [
    sidebar_pane(emit, model),
    @html.section(class="main") <| [
      main_toolbar(emit, model),
      main_pane(emit, model),
    ],
  ]
}

///|
fn app_class(model : Model) -> String {
  if model.sidebar_visible {
    "app"
  } else {
    "app sidebar-hidden"
  }
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
  let classes = if model.theme == theme {
    "theme-button active"
  } else {
    "theme-button"
  }
  @html.button(class=classes, on_click=emit(SetTheme(theme))) <| label
}

///|
fn sidebar_list(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  if model.sessions.is_empty() {
    return @html.div(class="sidebar-empty") <| "no sessions found"
  }
  let sections : Array[@html.Html] = []
  for group in sidebar_groups(model.sessions) {
    let rows = model.sessions
      .filter(row => session_group(row.root_label, row.is_marker) == group)
      .map(row => sidebar_row(emit, model, row))
    let collapsed = root_collapsed(model, group)
    let display = group_display(group)
    sections.push(
      @html.div(class=session_root_class(collapsed)) <| [
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
      ],
    )
  }
  @html.div(class="session-list") <| sections
}

///|
fn session_root_class(collapsed : Bool) -> String {
  if collapsed {
    "session-root collapsed"
  } else {
    "session-root"
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
/// Index of the last `/` or `\` in `p`, or -1 when there is none.
fn last_separator(p : String) -> Int {
  match (p.rev_find("/"), p.rev_find("\\")) {
    (Some(a), Some(b)) => if a > b { a } else { b }
    (Some(a), None) => a
    (None, Some(b)) => b
    (None, None) => -1
  }
}

///|
/// The directory portion of `p` (before the last separator), or `""` when `p`
/// has no directory component.
fn parent_dir(p : String) -> String {
  let i = last_separator(p)
  if i < 0 {
    ""
  } else {
    p[:i].to_owned()
  }
}

///|
/// The last path segment of `p`.
fn path_basename(p : String) -> String {
  let i = last_separator(p)
  if i < 0 {
    p
  } else {
    p[i + 1:].to_owned()
  }
}

///|
/// Drop a leading `./` so the default-scan labels (`./app/.openseek`) and an
/// absolute/bare form derive the same group. Without this, `parent_dir` of a
/// `./app` workspace is `.`, which would merge every direct workspace under one
/// `.` heading.
fn strip_dot_prefix(p : String) -> String {
  if p.has_prefix("./") {
    p[2:].to_owned()
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
/// workspaces (best-of-N / fleet) cluster under one heading; a workspace directly
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
) -> @html.Html {
  let selected = model.selected == Some(row.key)
  let label = if row.first_prompt.trim().is_empty() {
    row.id
  } else {
    row.first_prompt
  }
  let classes = if selected { "session-item selected" } else { "session-item" }
  @html.li(class=classes, on_click=emit(Select(row.key))) <| [
    @html.div(class="session-item-label") <| label,
    @html.div(class="session-item-meta") <| [
      @html.span(class="session-item-id") <| session_row_label(
        row.root_label,
        row.id,
        row.is_marker,
      ),
      last_active_view(row.last_active),
    ],
  ]
}

///|
fn main_pane(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  match model.selected {
    None =>
      @html.div(class="placeholder") <| (if model.sidebar_visible {
        "Select a session from the left to view it."
      } else {
        "Show sessions to select a session."
      })
    Some(key) =>
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
          let session = @viz.session_from_parse(
            parsed,
            id~,
            system_prompt=model.system_prompt,
          )
          let error_count = @viz.rendered_error_count(session, model.view_mode)
          @html.div(class=session_view_class(model)) <| [
            header_strip(model, id, row.map(row => row.root_label)),
            // Pin the view/args toggles and the error bar to the top of the
            // scroll area so they stay reachable while reading a long log.
            @html.div(class="sticky-toolbar") <| [
              mode_row(emit, model, parsed),
              error_bar(emit, model, error_count),
            ],
            @viz.render_notices(parsed),
            session_log_view(model, session, error_count),
          ]
        }
      }
  }
}

///|
fn header_strip(model : Model, id : String, root_label : String?) -> @html.Html {
  let prompt_note = if model.header_present {
    "session.json loaded"
  } else {
    "no session.json (events only)"
  }
  let root_note = match root_label {
    Some(root) => " · \{root}"
    None => ""
  }
  @html.header(class="header-strip") <| [
    @html.div(class="header-id") <| id,
    @html.div(class="header-meta") <| "\{model.status} · \{prompt_note}\{root_note}",
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
) -> @html.Html {
  @html.div(class="mode-row") <| [
    @html.div(class="mode-cluster") <| [
      mode_toggle(emit, model),
      args_toggle(emit, model),
    ],
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
  let classes = if model.show_original_args == show_original {
    "mode-button active"
  } else {
    "mode-button"
  }
  @html.button(class=classes, on_click=emit(SetArgsView(show_original))) <| label
}

///|
fn mode_button(
  emit : @cmd.Emit[Msg],
  model : Model,
  mode : @viz.ViewMode,
  label : String,
) -> @html.Html {
  let classes = if model.view_mode == mode {
    "mode-button active"
  } else {
    "mode-button"
  }
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
fn agent_step_count(parsed : @session_log.ParsedLog) -> Int {
  let mut count = 0
  let mut previous : @agent_session.SessionEvent? = None
  for event in parsed.events {
    if event_represents_agent_step(event, previous) {
      count += 1
    }
    previous = Some(event)
  }
  count
}

///|
fn event_represents_agent_step(
  event : @agent_session.SessionEvent,
  previous : @agent_session.SessionEvent?,
) -> Bool {
  match event.item() {
    Assistant(_) => true
    Terminal(Finished(_)) => terminal_finished_represents_agent_step(previous)
    _ => false
  }
}

///|
fn terminal_finished_represents_agent_step(
  previous : @agent_session.SessionEvent?,
) -> Bool {
  match previous {
    Some(event) =>
      match event.item() {
        Assistant(_) => false
        Tool(result) => result.tool_name() != "finish"
        _ => true
      }
    None => true
  }
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
  if first > 0L && last >= first {
    Some(last - first)
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
  let mut last = 0L
  for event in parsed.events {
    let stamp = event.unix_ms()
    if stamp > 0 {
      last = stamp
    }
  }
  if last > 0L {
    Some(last)
  } else {
    None
  }
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
  format_unix_ms_utc(milliseconds.to_double())
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
/// Add the `errors-only` class so the stylesheet folds the log down to failed
/// tool cards (and the turns containing them), and `show-original` so it swaps the
/// friendly tool-argument rendering for the raw JSON.
fn session_view_class(model : Model) -> String {
  match (model.errors_only, model.show_original_args) {
    (false, false) => "session-view"
    (true, false) => "session-view errors-only"
    (false, true) => "session-view show-original"
    (true, true) => "session-view errors-only show-original"
  }
}

///|
/// The "find failures" toolbar: a count, an errors-only filter toggle, and
/// prev/next jumps. Hidden when the view has no failures AND the filter is off,
/// so a clean session shows no chrome — but if the filter is on it stays visible
/// even at zero failures, otherwise "Errors only" could hide the whole log with
/// no way to switch it back off.
fn error_bar(emit : @cmd.Emit[Msg], model : Model, count : Int) -> @html.Html {
  if count == 0 && !model.errors_only {
    return @html.nothing
  }
  let toggle_class = if model.errors_only {
    "error-toggle active"
  } else {
    "error-toggle"
  }
  let children : Array[@html.Html] = []
  if count > 0 {
    children.push(
      @html.span(class="error-count") <| "🚩 \{count} tool error\{plural_s(count)}",
    )
  }
  children.push(
    @html.button(
      class=toggle_class,
      title="Show only failed tool results",
      on_click=emit(ToggleErrorsOnly),
    ) <| (if model.errors_only { "Errors only: on" } else { "Errors only" }),
  )
  // Jumps only make sense when there is something to jump to.
  if count > 0 {
    children.push(
      @html.button(
        class="error-jump",
        title="Scroll to the previous failure",
        on_click=emit(JumpToError(-1)),
      ) <| "↑ prev",
    )
    children.push(
      @html.button(
        class="error-jump",
        title="Scroll to the next failure",
        on_click=emit(JumpToError(1)),
      ) <| "↓ next",
    )
  }
  @html.div(class="error-bar") <| children
}

///|
/// The log, or a hint when the errors-only filter would hide everything (so the
/// pane never looks empty/broken when a clean view is filtered).
fn session_log_view(
  model : Model,
  session : @agent_session.Session,
  count : Int,
) -> @html.Html {
  if model.errors_only && count == 0 {
    @html.div(class="errors-only-empty") <| "No failed tool results in this view."
  } else {
    @viz.render_session(session, model.view_mode)
  }
}

///|
/// Number of failures the active view will draw, recomputed from the loaded log.
/// Returns 0 when nothing is loaded.
fn current_error_count(model : Model) -> Int {
  guard model.selected is Some(key) else { return 0 }
  guard model.parsed is Some(parsed) else { return 0 }
  let id = match session_row(model, key) {
    Some(row) => row.id
    None => key
  }
  let session = @viz.session_from_parse(
    parsed,
    id~,
    system_prompt=model.system_prompt,
  )
  @viz.rendered_error_count(session, model.view_mode)
}

///|
fn plural_s(n : Int) -> String {
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
  let rows : Array[SessionRow] = []
  for item in items {
    if session_row_of(item) is Some(row) {
      rows.push(row)
    }
  }
  Some(rows)
}

///|
fn session_row_of(json : Json) -> SessionRow? {
  guard json is Object(fields) else { return None }
  guard fields.get("id") is Some(String(id)) else { return None }
  let key = match fields.get("key") {
    Some(String(value)) => value
    _ => id
  }
  let root_label = match fields.get("root_label") {
    Some(String(value)) => value
    _ =>
      match fields.get("root") {
        Some(String(value)) => value
        _ => ""
      }
  }
  let first_prompt = match fields.get("first_prompt") {
    Some(String(value)) => value
    _ => ""
  }
  let last_active = match fields.get("last_active") {
    Some(Number(value, ..)) => Some(value.to_int64())
    _ => None
  }
  let is_marker = fields.get("is_marker") is Some(True)
  Some({ key, id, root_label, last_active, is_marker, first_prompt })
}

///|
/// Decode the `/api/sessions/<id>` envelope into a `LoadOutcome`. `header` is
/// the parsed `session.json` (or null); its `system_prompt` is lifted out when
/// present so the viewer can label the header strip and seed the model view.
fn parse_load(text : String) -> LoadOutcome {
  let json = @json.parse(text) catch { _ => return Malformed }
  guard json is Object(fields) else { return Malformed }
  let found = match fields.get("found") {
    Some(True) => true
    Some(False) => false
    _ => return Malformed
  }
  if !found {
    return NotFound
  }
  let events_text = match fields.get("events") {
    Some(String(value)) => value
    _ => return Malformed
  }
  let parsed = @viz.parse_events(events_text)
  let (system_prompt, header_present) = match fields.get("header") {
    Some(Object(header)) =>
      (
        match header.get("system_prompt") {
          Some(String(prompt)) => prompt
          _ => ""
        },
        true,
      )
    _ => ("", false)
  }
  let log_bytes = match fields.get("events_bytes") {
    Some(Number(value, ..)) => value.to_int64()
    _ => events_text.length().to_int64()
  }
  Loaded(parsed, system_prompt, header_present, log_bytes)
}
