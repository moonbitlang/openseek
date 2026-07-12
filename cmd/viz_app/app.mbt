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
/// system prompt lifted from the session file's header line; the typed
/// `Session` and its model projection are rebuilt in `view` so the two view
/// modes always agree with the bytes on disk.
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
  drop_ticket : Int
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
/// Colour theme. `System` is the default and follows the OS via a CSS
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
  FileDropped(String, Int64, @dom.Blob)
  DroppedFileRead(Int, String, Int64, Result[String, Error])
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
/// Whether the freshly fetched session list should auto-open its only entry:
/// standalone exports only, exactly one session, and nothing already on
/// screen (a selection in flight or a dropped file must not be clobbered).
fn should_auto_open(
  standalone : Bool,
  sessions : Array[SessionRow],
  selected~ : String?,
  dropped~ : String?,
) -> Bool {
  standalone && sessions.length() == 1 && selected is None && dropped is None
}

///|
/// The view mode to start in: an explicit `v=` in the URL hash (a restored
/// refresh) wins over the standalone/live defaults.
fn restored_view_mode(hash_view : String, standalone : Bool) -> @viz.ViewMode {
  match hash_view {
    "raw" => RawLog
    "model" => ModelView
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
fn init_model() -> Model {
  {
    sessions: [],
    selected: None,
    pending_restore_key: match hash_param("s") {
      "" => None
      key => Some(key)
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
    show_original_args: false,
  }
}

// ---- update ----------------------------------------------------------------

///|
fn update(emit : @cmd.Emit[Msg], msg : Msg, model : Model) -> (@cmd.Cmd, Model) {
  match msg {
    SessionsFetched(Ok(text)) =>
      match parse_session_rows(text) {
        Some(sessions) => {
          let listed = {
            ..model,
            sessions,
            pending_restore_key: None,
            collapsed_roots: prune_collapsed_roots(
              model.collapsed_roots,
              sessions,
            ),
            status: list_status(model, "\{sessions.length()} session(s)"),
          }
          // A refresh restores the session named in the URL hash — in the
          // live viewer and in exports alike. Otherwise a standalone export
          // holding exactly one session opens it immediately; live servers
          // keep the explicit click, since their list refreshes must never
          // yank the user off a session.
          let untouched = model.selected is None && model.dropped is None
          match model.pending_restore_key {
            Some(key) if untouched && sessions.iter().any(row => row.key == key) =>
              update(emit, Select(key), listed)
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
      let mode = view_mode_value(model.view_mode)
      (
        @cmd.batch([command, @cmd.effect(() => set_hash_session(key, mode))]),
        {
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
                  // The log renders in this same cycle; once it is in the
                  // DOM, scroll back to the seq= position saved in the hash.
                  @cmd.effect(() => restore_scroll_to_hash_seq()),
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
        { ..model, view_mode: mode },
      )
    }
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

// ---- URL-hash position state -------------------------------------------------
// The hash carries `s=<session key>&v=<raw|model>&seq=<n>` so a refresh (or a
// shared link) lands back on the same session, view, and step. `seq` is a
// durable event sequence — the `seq-N` card anchors — so it survives log
// growth; all writes use replaceState so scrolling never spams history.

///|
/// One decoded parameter from the location hash, `""` when absent (or when
/// running without a browser, e.g. under tests).
extern "js" fn hash_param(name : String) -> String =
  #|(name) => {
  #|  if (typeof location === 'undefined') return '';
  #|  try {
  #|    return new URLSearchParams(location.hash.slice(1)).get(name) || '';
  #|  } catch (e) {
  #|    return '';
  #|  }
  #|}

///|
/// Record the selected session (and current view) in the hash. Switching from
/// one session to a DIFFERENT one drops the stale `seq=` position;
/// re-selecting the same one keeps it, and so does the first selection of the
/// page (no `s=` yet — an auto-opened export restoring `#seq=` relies on it).
extern "js" fn set_hash_session(key : String, view : String) -> Unit =
  #|(key, view) => {
  #|  if (typeof location === 'undefined') return;
  #|  const params = new URLSearchParams(location.hash.slice(1));
  #|  const previous = params.get('s');
  #|  if (previous !== null && previous !== key) params.delete('seq');
  #|  params.set('s', key);
  #|  params.set('v', view);
  #|  history.replaceState(null, '', '#' + params.toString());
  #|}

///|
/// Record the active view mode in the hash, keeping session and position.
extern "js" fn set_hash_view(view : String) -> Unit =
  #|(view) => {
  #|  if (typeof location === 'undefined') return;
  #|  const params = new URLSearchParams(location.hash.slice(1));
  #|  params.set('v', view);
  #|  history.replaceState(null, '', '#' + params.toString());
  #|}

///|
/// Scroll the log back to the hash's `seq=` position. A large log may take
/// several frames to commit, so this polls briefly until the `seq-` anchors
/// exist. The exact anchor may be absent in the current view (compacted away
/// in the model projection, or a result card that carries a pair id
/// instead), so the lookup falls back to the nearest following anchor.
extern "js" fn restore_scroll_to_hash_seq() -> Unit =
  #|() => {
  #|  if (typeof location === 'undefined') return;
  #|  const attempt = (tries) => {
  #|    const params = new URLSearchParams(location.hash.slice(1));
  #|    const want = parseInt(params.get('seq') || '', 10);
  #|    if (!Number.isFinite(want)) return;
  #|    const el = window.__openseekNearestSeq && window.__openseekNearestSeq(want);
  #|    if (el) {
  #|      el.scrollIntoView({ block: 'start' });
  #|      return;
  #|    }
  #|    if (tries > 0) setTimeout(() => attempt(tries - 1), 100);
  #|  };
  #|  requestAnimationFrame(() => requestAnimationFrame(() => attempt(50)));
  #|}

///|
/// Install the position tracker: a rAF-throttled scroll listener that writes
/// the topmost visible `seq-` anchor into the hash's `seq=` (replaceState, no
/// history spam) and moves the scrubber's `current` mark, plus a delegated
/// click handler that makes `.step-seg` segments jump to their step. Also
/// defines the shared nearest-anchor lookup `restore_scroll_to_hash_seq` uses.
extern "js" fn install_position_tracker() -> Unit =
  #|() => {
  #|  if (typeof document === 'undefined') return;
  #|  // Hidden cards (errors-only filter, collapsed turns) report zeroed
  #|  // rects, which would let the scan pick an anchor no scroll can reveal —
  #|  // only visible anchors count.
  #|  const visible = (el) => el && el.getClientRects().length > 0;
  #|  const anchors = () =>
  #|    Array.from(document.querySelectorAll('[id^="seq-"]')).filter(visible);
  #|  window.__openseekNearestSeq = (want) => {
  #|    const exact = document.getElementById('seq-' + want);
  #|    if (visible(exact)) return exact;
  #|    const all = anchors();
  #|    return all.find((el) => parseInt(el.id.slice(4), 10) >= want) || all[all.length - 1] || null;
  #|  };
  #|  const markScrubber = (seq) => {
  #|    let current = null;
  #|    for (const seg of document.querySelectorAll('.step-seg')) {
  #|      seg.classList.remove('current');
  #|      if (+seg.dataset.seq <= seq) current = seg;
  #|    }
  #|    if (current) current.classList.add('current');
  #|  };
  #|  let ticking = false;
  #|  document.addEventListener('scroll', () => {
  #|    if (ticking) return;
  #|    ticking = true;
  #|    requestAnimationFrame(() => {
  #|      ticking = false;
  #|      const all = anchors();
  #|      if (!all.length) return;
  #|      // The current card: the last anchor at or above the reading line.
  #|      // The cutoff must sit BELOW the anchors' scroll-margin-top (105px in
  #|      // the stylesheet): a jump parks its target exactly at the margin,
  #|      // and a tighter cutoff would record the preceding card instead.
  #|      let best = null;
  #|      for (const el of all) {
  #|        if (el.getBoundingClientRect().top <= 110) best = el;
  #|        else break;
  #|      }
  #|      const seq = (best || all[0]).id.slice(4);
  #|      const params = new URLSearchParams(location.hash.slice(1));
  #|      if (params.get('seq') !== seq) {
  #|        params.set('seq', seq);
  #|        history.replaceState(null, '', '#' + params.toString());
  #|      }
  #|      markScrubber(+seq);
  #|    });
  #|  }, { capture: true, passive: true });
  #|  document.addEventListener('click', (event) => {
  #|    if (!(event.target instanceof Element)) return;
  #|    const seg = event.target.closest('.step-seg');
  #|    if (!seg || !seg.dataset.seq) return;
  #|    const el = window.__openseekNearestSeq(+seg.dataset.seq);
  #|    if (!el) return;
  #|    const params = new URLSearchParams(location.hash.slice(1));
  #|    params.set('seq', el.id.slice(4));
  #|    history.replaceState(null, '', '#' + params.toString());
  #|    el.scrollIntoView({ block: 'start' });
  #|  });
  #|  // Instant scrubber tooltip: shows each segment's data-label ("Step
  #|  // N/M[ · has failures]") the moment the pointer touches it — a native
  #|  // title tooltip would lag behind the OS hover delay while sweeping.
  #|  const tip = document.createElement('div');
  #|  tip.className = 'scrubber-tip';
  #|  tip.style.display = 'none';
  #|  document.body.appendChild(tip);
  #|  const hideTip = () => { tip.style.display = 'none'; };
  #|  document.addEventListener('mouseover', (event) => {
  #|    if (!(event.target instanceof Element)) return hideTip();
  #|    const seg = event.target.closest('.step-seg');
  #|    if (!seg || !seg.dataset.label) return hideTip();
  #|    tip.textContent = seg.dataset.label;
  #|    tip.style.display = 'block';
  #|    const rect = seg.getBoundingClientRect();
  #|    const x = Math.min(
  #|      Math.max(rect.left + rect.width / 2 - tip.offsetWidth / 2, 8),
  #|      window.innerWidth - tip.offsetWidth - 8,
  #|    );
  #|    tip.style.left = x + 'px';
  #|    tip.style.top = (rect.bottom + 6) + 'px';
  #|  });
  #|  document.addEventListener('scroll', hideTip, { capture: true, passive: true });
  #|  // The scrubber sits near the top edge, so the pointer can exit straight
  #|  // into browser chrome — no further mouseover ever fires to hide the tip.
  #|  document.addEventListener('mouseleave', hideTip);
  #|  window.addEventListener('blur', hideTip);
  #|}

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
/// Whether a self-contained export (see `cmd/viz_server --export`) baked a
/// response for `url` into `window.__OPENSEEK_DATA__`. False in a normal server
/// build, where the global is absent and every lookup misses.
extern "js" fn embedded_has(url : String) -> Bool = "(url) => (typeof window !== 'undefined') && !!window.__OPENSEEK_DATA__ && Object.prototype.hasOwnProperty.call(window.__OPENSEEK_DATA__, url)"

///|
/// The baked response body for `url`. Only called after `embedded_has` is true.
extern "js" fn embedded_get(url : String) -> String = "(url) => window.__OPENSEEK_DATA__[url]"

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
/// `rabbita/dom` binds `DataTransfer.items` but not `DataTransfer.files`; a
/// dropped `File` is a `Blob` subtype, which is all the reader needs.
extern "js" fn data_transfer_file_count(transfer : @dom.DataTransfer) -> Int = "(t) => (t.files ? t.files.length : 0)"

///|
extern "js" fn data_transfer_file_name(
  transfer : @dom.DataTransfer,
  index : Int,
) -> String = "(t, i) => t.files[i].name"

///|
extern "js" fn data_transfer_file(
  transfer : @dom.DataTransfer,
  index : Int,
) -> @dom.Blob = "(t, i) => t.files[i]"

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
  @html.div(class=app_class(model), attrs=drop_target_attrs(emit)) <| [
    sidebar_pane(emit, model),
    @html.section(class="main") <| [
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
  let sections : Array[@html.Html] = []
  for group in sidebar_groups(model.sessions) {
    let rows = model.sessions
      .filter(row => session_group(row.root_label, row.is_marker) == group)
      .map(row => sidebar_row(emit, model, row))
    let collapsed = root_collapsed(model, group)
    let display = group_display(group)
    sections.push(
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
      ],
    )
  }
  @html.div(class="session-list") <| sections
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
    (Some(a), None) | (None, Some(a)) => a
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
  let classes = class_with("session-item", "selected", selected)
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
  @html.div(class=session_view_class(model)) <| [
    header_strip(model, id, root_label),
    // Pin the view/args toggles and the error bar to the top of the
    // scroll area so they stay reachable while reading a long log.
    @html.div(class="sticky-toolbar") <| [
      mode_row(emit, model, parsed, @viz.step_scrubber(session)),
      error_bar(emit, model, error_count),
    ],
    @viz.render_notices(parsed),
    session_log_view(model, session, error_count),
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
fn agent_step_count(parsed : @session_log.ParsedLog) -> Int {
  let mut count = 0
  let mut previous : @agent_session.SessionEvent? = None
  let mut finish_in_batch = false
  for event in parsed.events {
    if event_represents_agent_step(event, previous, finish_in_batch) {
      count += 1
    }
    // A checkpoint Summary can sit between a finish-tool result and its
    // terminal (compact-on-finish); skip it when looking backward so the
    // terminal is still attributed to the finish call.
    match event.item() {
      Tool(result) =>
        if result.tool_name() == "finish" {
          finish_in_batch = true
        }
      Summary(_) => ()
      _ => finish_in_batch = false
    }
    if !(event.item() is Summary(_)) {
      previous = Some(event)
    }
  }
  count
}

///|
fn event_represents_agent_step(
  event : @agent_session.SessionEvent,
  previous : @agent_session.SessionEvent?,
  finish_in_batch : Bool,
) -> Bool {
  match event.item() {
    Assistant(_) => true
    Terminal(Finished(message)) =>
      // A context-ceiling yield's terminal is synthetic, not a model step.
      !message.has_prefix(@agent_session.ContextYieldAnswerPrefix) &&
      terminal_finished_represents_agent_step(previous, finish_in_batch)
    _ => false
  }
}

///|
/// Tool results are recorded in CALL order, so a finish result may be
/// followed by same-batch skip notes; `finish_in_batch` — a finish result
/// seen since the last assistant message — is the completion signal, not
/// "the finish result came last".
fn terminal_finished_represents_agent_step(
  previous : @agent_session.SessionEvent?,
  finish_in_batch : Bool,
) -> Bool {
  if finish_in_batch {
    return false
  }
  match previous {
    Some(event) =>
      match event.item() {
        Assistant(_) => false
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
  let toggle_class = class_with("error-toggle", "active", model.errors_only)
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
/// Number of failures the active view will draw, recomputed from the loaded
/// log — served or dropped; the session id plays no part in the count.
/// Returns 0 when nothing is loaded.
fn current_error_count(model : Model) -> Int {
  guard model.parsed is Some(parsed) else { return 0 }
  let session = @viz.session_from_parse(
    parsed,
    id="",
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
  Some(items.filter_map(session_row_of))
}

///|
fn session_row_of(json : Json) -> SessionRow? {
  guard json
    is {
      "id": String(id),
      "first_prompt"? : Some(String(first_prompt))
      | _ with first_prompt = "",
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
    { "root"? : Some(String(value)) | _ with value = "", .. } => value
    _ => ""
  }
  let last_active = match json {
    { "last_active": Number(value, ..), .. } => Some(value.to_int64())
    _ => None
  }
  let is_marker = json is { "is_marker": True, .. }
  Some({ key, id, root_label, last_active, is_marker, first_prompt })
}

///|
/// Decode the `/api/sessions/<id>` envelope into a `LoadOutcome`. `events` is
/// the raw session-file text; the header record on its first line carries the
/// system prompt, lifted out so the viewer can label the header strip and seed
/// the model view.
fn parse_load(text : String) -> LoadOutcome {
  let json = @json.parse(text) catch { _ => return Malformed }
  match json {
    { "found": False, .. } => NotFound
    { "found": True, "events": String(events_text), .. } => {
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
fn parsed_log(session : @agent_session.Session) -> @session_log.ParsedLog {
  {
    header: None,
    events: [
      for event in session.events() => event
    ],
    errors: [],
    partial_tail: false,
  }
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
  inspect(end_time_label(parsed), content="1970-01-01 00:02 UTC")
}

///|
test "session metadata counts terminal final answers as steps" {
  let parsed = parsed_log(
    @agent_session.Session(SessionId("terminal-step"), system_prompt="")
    .append(User(UserMessage("hi")))
    .append(Terminal(Finished("done"))),
  )
  inspect(agent_step_count(parsed), content="1")
}

///|
test "session metadata does not double count finish tool terminals" {
  let parsed = parsed_log(
    @agent_session.Session(SessionId("finish-step"), system_prompt="")
    .append(User(UserMessage("hi")))
    .append(Assistant(AssistantMessage("")))
    .append(
      Tool(
        ToolResult(
          tool_call_id="finish_1",
          tool_name="finish",
          content="finished: done",
        ),
      ),
    )
    .append(Terminal(Finished("done"))),
  )
  inspect(agent_step_count(parsed), content="1")
}

///|
test "absolute time labels format UTC timestamps" {
  inspect(absolute_time_label(0L), content="1970-01-01 00:00 UTC")
  inspect(last_active_label(Some(0L)), content="1970-01-01 00:00 UTC")
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
  let selected = { ..init_model(), selected: Some("0|remote"), loading: true }
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
test "stale dropped-file reads are discarded" {
  let emit = stub_emit()
  let model = { ..init_model(), drop_ticket: 2 }
  // A read issued before the user moved on carries an old ticket: ignored.
  let (_, unchanged) = update(
    emit,
    DroppedFileRead(1, "old.jsonl", 1L, Ok("")),
    model,
  )
  debug_inspect(unchanged.dropped, content="None")
  // The read matching the current ticket applies.
  let (_, applied) = update(
    emit,
    DroppedFileRead(2, "new.jsonl", 1L, Ok("")),
    model,
  )
  debug_inspect(applied.dropped, content="Some(\"new.jsonl\")")
}

///|
test "a late session list does not clobber the dropped-file status" {
  let emit = stub_emit()
  let dropped = apply_dropped_file(
    init_model(),
    "run.jsonl",
    10L,
    (
      #|{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":"hi"}}}
      #|
    ),
  )
  let before = dropped.status
  let (_, listed) = update(emit, SessionsFetched(Ok("[]")), dropped)
  inspect(listed.status == before, content="true")
  inspect(listed.sessions.length(), content="0")
  // Without an active dropped file the list outcome still updates the status.
  let (_, plain) = update(emit, SessionsFetched(Ok("[]")), init_model())
  inspect(plain.status, content="0 session(s)")
}

///|
test "selecting a session invalidates an in-flight dropped-file read" {
  let emit = stub_emit()
  let model = { ..init_model(), drop_ticket: 5 }
  let (_, selected) = update(emit, Select("0|remote"), model)
  inspect(selected.drop_ticket, content="6")
  debug_inspect(selected.selected, content="Some(\"0|remote\")")
  // The read the old drop issued now carries a stale ticket.
  let (_, unchanged) = update(
    emit,
    DroppedFileRead(5, "old.jsonl", 1L, Ok("")),
    selected,
  )
  debug_inspect(unchanged.dropped, content="None")
  debug_inspect(unchanged.selected, content="Some(\"0|remote\")")
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
test "sidebar_groups clusters by container, in listing order, no duplicates" {
  let rows = [
    // Two sibling run workspaces share the /tmp/ab container.
    marker_row("0|a", "run", "/tmp/ab/A-1/.openseek"),
    marker_row("1|b", "run", "/tmp/ab/B-1/.openseek"),
    // Default-scan "./" workspaces stay separate (not merged under ".").
    marker_row("2|c", "c", "./app/.openseek"),
    marker_row("3|d", "d", "./lib/.openseek"),
    marker_row("4|e", "e", "./.openseek"),
  ]
  @debug.debug_inspect(
    sidebar_groups(rows),
    content=(
      #|["/tmp/ab", "app", "lib", ""]
    ),
  )
}

///|
fn marker_row(key : String, id : String, root_label : String) -> SessionRow {
  { key, id, root_label, last_active: None, is_marker: true, first_prompt: "" }
}

///|
fn direct_row(key : String, id : String, root_label : String) -> SessionRow {
  { key, id, root_label, last_active: None, is_marker: false, first_prompt: "" }
}

///|
/// A no-op `Emit` for `update` tests that ignore the emitted commands.
fn stub_emit() -> @cmd.Emit[Msg] {
  Emit(_ => @cmd.none)
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
test "sidebar_groups keeps unrelated direct stores separate" {
  let rows = [
    direct_row("0|a", "a", "/srv/store-a"),
    direct_row("1|b", "b", "/srv/store-b"),
  ]
  @debug.debug_inspect(
    sidebar_groups(rows),
    content=(
      #|["/srv/store-a", "/srv/store-b"]
    ),
  )
}

///|
test "collapsed group helpers toggle and prune stale groups" {
  let rows = [
    marker_row("0|a", "a", "app/.openseek"),
    marker_row("1|b", "b", "lib/.openseek"),
  ]
  let collapsed = toggle_collapsed_root([], "app")
  @debug.debug_inspect(collapsed, content="[\"app\"]")
  let expanded = toggle_collapsed_root(collapsed, "app")
  @debug.debug_inspect(expanded, content="[]")
  @debug.debug_inspect(
    prune_collapsed_roots(["app", "stale"], rows),
    content="[\"app\"]",
  )
}

///|
test "app class tracks sidebar visibility" {
  let visible = { ..init_model(), sidebar_visible: true }
  let hidden = { ..init_model(), sidebar_visible: false }
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
/// An `s=` session key parsed from the URL hash is honored by the first
/// session listing — in the live viewer and exports alike — and consumed
/// whether or not it matches, so a stale key cannot re-fire on refreshes of
/// the list.
test "the hash session key restores the selection on the first listing" {
  let emit = stub_emit()
  let listing =
    #|[{"key":"k1","id":"s1"},{"key":"k2","id":"s2"}]
  let pending = { ..init_model(), pending_restore_key: Some("k2") }
  let (_, restored) = update(emit, SessionsFetched(Ok(listing)), pending)
  debug_inspect(restored.selected, content="Some(\"k2\")")
  debug_inspect(restored.pending_restore_key, content="None")
  // An unknown key is consumed without selecting anything.
  let stale = { ..init_model(), pending_restore_key: Some("gone") }
  let (_, ignored) = update(emit, SessionsFetched(Ok(listing)), stale)
  debug_inspect(ignored.selected, content="None")
  debug_inspect(ignored.pending_restore_key, content="None")
  // An existing selection is never yanked by a late restore key.
  let busy = {
    ..init_model(),
    pending_restore_key: Some("k2"),
    selected: Some("k1"),
  }
  let (_, kept) = update(emit, SessionsFetched(Ok(listing)), busy)
  debug_inspect(kept.selected, content="Some(\"k1\")")
}

///|
/// The hash's `v=` overrides the standalone/live view-mode defaults on
/// restore; anything else falls through to them.
test "the hash view mode wins over the defaults" {
  assert_true(restored_view_mode("raw", false) == RawLog)
  assert_true(restored_view_mode("model", true) == ModelView)
  assert_true(restored_view_mode("", true) == RawLog)
  assert_true(restored_view_mode("", false) == ModelView)
  assert_true(restored_view_mode("nonsense", false) == ModelView)
  inspect(view_mode_value(RawLog), content="raw")
  inspect(view_mode_value(ModelView), content="model")
}

///|
/// Only a standalone export with exactly one session and an untouched pane
/// auto-opens; a live server list, several sessions, an existing selection,
/// or a dropped file all keep the explicit click.
test "single-session standalone exports auto-open their session" {
  let row = direct_row("k1", "s1", "")
  let other = { ..row, key: "k2", id: "s2" }
  assert_true(should_auto_open(true, [row], selected=None, dropped=None))
  assert_false(should_auto_open(false, [row], selected=None, dropped=None))
  assert_false(
    should_auto_open(true, [row, other], selected=None, dropped=None),
  )
  assert_false(should_auto_open(true, [], selected=None, dropped=None))
  assert_false(should_auto_open(true, [row], selected=Some("k1"), dropped=None))
  assert_false(
    should_auto_open(true, [row], selected=None, dropped=Some("f.jsonl")),
  )
}
