///|
/// One row of the `/api/sessions` listing shown in the sidebar. The server
/// already returns rows most-recently-active first, so the row only needs an id
/// and a human label.
struct SessionRow {
  key : String
  id : String
  root_label : String
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
  view_mode : @viz.ViewMode
  theme : Theme
  sidebar_visible : Bool
  collapsed_roots : Array[String]
  loading : Bool
  status : String
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
  SetTheme(Theme)
  ToggleSidebar
  ToggleRoot(String)
}

///|
/// Outcome of decoding the `/api/sessions/<id>` envelope. `rabbita/http` reports
/// any completed response as `Ok`, so absence and malformed payloads are
/// distinguished here from the body, not the HTTP status.
enum LoadOutcome {
  Loaded(@session_log.ParsedLog, String, Bool)
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
    view_mode: ModelView,
    theme: Light,
    sidebar_visible: true,
    collapsed_roots: [],
    loading: false,
    status: "loading sessions…",
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
              Loaded(parsed, system_prompt, header_present) =>
                (
                  @cmd.none,
                  {
                    ..model,
                    parsed: Some(parsed),
                    system_prompt,
                    header_present,
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
  @html.div(class=app_class(model), [
    sidebar_pane(emit, model),
    @html.section(class="main", [
      main_toolbar(emit, model),
      main_pane(emit, model),
    ]),
  ])
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
  @html.aside(class="sidebar", [
    @html.div(class="sidebar-head", [
      @html.div(class="sidebar-title-row", [
        @html.h1(class="brand", "OpenSeek sessions"),
        @html.button(
          class="sidebar-hide-button",
          title="Hide sessions",
          on_click=emit(ToggleSidebar),
          "Hide",
        ),
      ]),
      @html.div(class="status", model.status),
    ]),
    sidebar_list(emit, model),
    theme_toggle(emit, model),
  ])
}

///|
fn main_toolbar(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  if model.sidebar_visible {
    return @html.nothing
  }
  @html.div(class="main-toolbar", [
    @html.button(
      class="sidebar-show-button",
      title="Show sessions",
      on_click=emit(ToggleSidebar),
      "Show sessions",
    ),
  ])
}

///|
fn theme_toggle(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="theme-toggle", [
    theme_button(emit, model, Light, "Light"),
    theme_button(emit, model, Dark, "Dark"),
    theme_button(emit, model, System, "System"),
  ])
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
  @html.button(class=classes, on_click=emit(SetTheme(theme)), label)
}

///|
fn sidebar_list(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  if model.sessions.is_empty() {
    return @html.div(class="sidebar-empty", "no sessions found")
  }
  let sections : Array[@html.Html] = []
  for root in sidebar_roots(model.sessions) {
    let rows : Array[@html.Html] = [
      for row in model.sessions if row.root_label == root => {
        sidebar_row(emit, model, row)
      }
    ]
    let collapsed = root_collapsed(model, root)
    sections.push(
      @html.div(class=session_root_class(collapsed), [
        @html.button(
          class="session-root-toggle",
          title=if collapsed { "Expand \{root}" } else { "Collapse \{root}" },
          on_click=emit(ToggleRoot(root)),
          [
            @html.span(
              class="session-root-caret",
              if collapsed {
                "▸"
              } else {
                "▾"
              },
            ),
            @html.span(class="session-root-name", root),
            @html.span(class="session-root-count", rows.length().to_string()),
          ],
        ),
        if collapsed {
          @html.nothing
        } else {
          @html.ul(class="session-root-sessions", rows)
        },
      ]),
    )
  }
  @html.div(class="session-list", sections)
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
fn sidebar_roots(rows : Array[SessionRow]) -> Array[String] {
  let roots : Array[String] = []
  for row in rows {
    if !roots.contains(row.root_label) {
      roots.push(row.root_label)
    }
  }
  roots
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
  let roots = sidebar_roots(rows)
  collapsed_roots.filter(root => roots.contains(root))
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
  @html.li(class=classes, on_click=emit(Select(row.key)), [
    @html.div(class="session-item-label", label),
    @html.div(class="session-item-id", row.id),
  ])
}

///|
fn main_pane(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  match model.selected {
    None =>
      @html.div(
        class="placeholder",
        if model.sidebar_visible {
          "Select a session from the left to view it."
        } else {
          "Show sessions to select a session."
        },
      )
    Some(key) =>
      match model.parsed {
        None =>
          if model.loading {
            @html.div(
              class="placeholder",
              "Loading \{session_label(model, key)}…",
            )
          } else {
            @html.div(class="placeholder", model.status)
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
          @html.div(class="session-view", [
            header_strip(model, id, row.map(row => row.root_label)),
            mode_toggle(emit, model),
            @viz.render_notices(parsed),
            @viz.render_session(session, model.view_mode),
          ])
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
  @html.header(class="header-strip", [
    @html.div(class="header-id", id),
    @html.div(
      class="header-meta",
      "\{model.status} · \{prompt_note}\{root_note}",
    ),
  ])
}

///|
fn mode_toggle(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="mode-toggle", [
    mode_button(emit, model, RawLog, "Raw log"),
    mode_button(emit, model, ModelView, "Model view"),
  ])
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
  @html.button(class=classes, on_click=emit(SetMode(mode)), label)
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
  Some({ key, id, root_label, first_prompt })
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
  Loaded(parsed, system_prompt, header_present)
}
