// Browser fixture for the cursor/input/event parity child. Playwright drives
// actual trusted key and pointer events against the focusable editor root;
// these controls expose only deterministic setup/readback plus the public
// cursor-event stream.

///|
priv struct CursorInputHoverProvider {}

///|
impl @language.HoverProvider for CursorInputHoverProvider with fn provide_hover(
  _self,
  model,
  position,
  _token,
) {
  if position.line_number == 2 && position.column >= 3 && position.column <= 7 {
    Some({
      range: Range(2, 3, 2, 7),
      contents: [PlainText("cursor input hover")],
    })
  } else {
    ignore(model)
    None
  }
}

///|
fn cursor_input_source() -> String {
  let source =
    #|alpha
    #|  beta gamma delta
    #|wrap alpha beta gamma delta epsilon zeta eta theta iota kappa lambda
    #|
    #|  ; punctuation value
    #|line six
    #|line seven
    #|line eight
    #|line nine
    #|line ten
    #|line eleven
    #|omega
  source
}

///|
fn cursor_reason_name(reason : @editor_api.CursorChangeReason) -> String {
  match reason {
    NotSet => "NotSet"
    ContentFlush => "ContentFlush"
    RecoverFromMarkers => "RecoverFromMarkers"
    Explicit => "Explicit"
    Paste => "Paste"
    Undo => "Undo"
    Redo => "Redo"
  }
}

///|
fn cursor_input_state_json(
  viewer : @viewer.Viewer,
  model : @model.TextModel,
) -> String {
  match (viewer.get_position(), viewer.get_selection()) {
    (Some(position), Some(selection)) => {
      let anchor = selection.get_selection_start()
      let active = selection.get_position()
      "{\"position\":{\"line\":\{position.line_number},\"column\":\{position.column}},\"selection\":{\"anchorLine\":\{anchor.line_number},\"anchorColumn\":\{anchor.column},\"activeLine\":\{active.line_number},\"activeColumn\":\{active.column}},\"modelVersionId\":\{model.get_version_id()},\"hostVersion\":\{model.version},\"hasTextFocus\":\{viewer.has_text_focus()}}"
    }
    _ => "null"
  }
}

///|
pub fn run_cursor_input_events_test() -> Unit {
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else { return }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell cursor-input-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;")
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host cursor-input-host")
  host.set_attribute("style", "height:120px;width:260px;")
  shell.append_child(host.as_node())
  app.append_child(shell.as_node())
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/cursor-input.txt",
    ),
    "cursor-input.txt",
    "plaintext",
    73,
    "cursor-input-rev-1",
    cursor_input_source(),
  )
  let languages = @languages.Languages()
  languages.register_hover_provider(LanguageId("plaintext"), CursorInputHoverProvider::{
  })
  |> ignore
  let log_service = @log.LogService()
  let log_handle = log_service.log_handle()
  let services = @viewer.ViewerServices(
    languages=languages.language_handle(log_handle),
    log_service=log_handle,
  )
  let viewer = @viewer.Viewer::create(
    host,
    services~,
    options=ViewerOptions(soft_wrap=true, smooth_scrolling=false),
  )
  viewer.on_did_change_model_content(event => {
    record_cursor_content_event(event.version_id)
  })
  |> ignore
  viewer.on_did_change_cursor_position(event => {
    let (committed_line, committed_column) = match viewer.get_position() {
      Some(committed) => (Json(committed.line_number), Json(committed.column))
      None => (Json::null(), Json::null())
    }
    record_cursor_event(
      Json({
        "type": Json("position"),
        "line": Json(event.position.line_number),
        "column": Json(event.position.column),
        "committedLine": committed_line,
        "committedColumn": committed_column,
        "secondaryCount": Json(event.secondary_positions.length()),
        "source": Json(event.source),
        "reason": Json(cursor_reason_name(event.reason)),
      }).stringify(),
    )
  })
  |> ignore
  viewer.on_did_change_cursor_selection(event => {
    let anchor = event.selection.get_selection_start()
    let active = event.selection.get_position()
    let old_selection_count = match event.old_selections {
      Some(selections) => Json(selections.length())
      None => Json::null()
    }
    let (old_anchor_line, old_anchor_column, old_active_line, old_active_column) = match
      event.old_selections {
      Some([old, ..]) => {
        let old_anchor = old.get_selection_start()
        let old_active = old.get_position()
        (
          Json(old_anchor.line_number),
          Json(old_anchor.column),
          Json(old_active.line_number),
          Json(old_active.column),
        )
      }
      _ => (Json::null(), Json::null(), Json::null(), Json::null())
    }
    let (
      committed_anchor_line,
      committed_anchor_column,
      committed_active_line,
      committed_active_column,
    ) = match viewer.get_selection() {
      Some(committed) => {
        let committed_anchor = committed.get_selection_start()
        let committed_active = committed.get_position()
        (
          Json(committed_anchor.line_number),
          Json(committed_anchor.column),
          Json(committed_active.line_number),
          Json(committed_active.column),
        )
      }
      None => (Json::null(), Json::null(), Json::null(), Json::null())
    }
    record_cursor_event(
      Json({
        "type": Json("selection"),
        "anchorLine": Json(anchor.line_number),
        "anchorColumn": Json(anchor.column),
        "activeLine": Json(active.line_number),
        "activeColumn": Json(active.column),
        "secondaryCount": Json(event.secondary_selections.length()),
        "oldSelectionCount": old_selection_count,
        "oldAnchorLine": old_anchor_line,
        "oldAnchorColumn": old_anchor_column,
        "oldActiveLine": old_active_line,
        "oldActiveColumn": old_active_column,
        "committedAnchorLine": committed_anchor_line,
        "committedAnchorColumn": committed_anchor_column,
        "committedActiveLine": committed_active_line,
        "committedActiveColumn": committed_active_column,
        "oldModelVersionId": Json(event.old_model_version_id),
        "modelVersionId": Json(event.model_version_id),
        "source": Json(event.source),
        "reason": Json(cursor_reason_name(event.reason)),
      }).stringify(),
    )
  })
  |> ignore
  viewer.set_model(Some(model))
  viewer.handle_initialized()
  // Keep one caller-owned, focusable ViewZone below the fixture's last model
  // line. It does not perturb the visible cursor scenarios, while real DOM
  // Selection/copy and bubbling key events can exercise the editor-input
  // ownership boundary in this same public-Viewer fixture.
  let zone_node = document.create_element("div")
  zone_node.set_attribute("class", "cursor-input-view-zone")
  let zone_text = document.create_element("span")
  zone_text.set_attribute("class", "cursor-input-view-zone-text")
  zone_text.set_inner_html("caller-owned zone text")
  let zone_link = document.create_element("a")
  zone_link.set_attribute("class", "cursor-input-view-zone-link")
  zone_link.set_attribute("href", "#cursor-input-zone-target")
  zone_link.set_inner_html("caller-owned zone link")
  zone_node.append_child(zone_text.as_node())
  zone_node.append_child(zone_link.as_node())
  viewer.change_view_zones(accessor => {
    accessor.add_zone(
      @viewer.view_zone(
        12,
        zone_node,
        suppress_mouse_down=false,
        height_in_px=28.0,
      ),
    )
    |> ignore
  })
  guard viewer.get_dom_node() is Some(root) else { return }
  install_cursor_input_controls(
    root,
    zone_text,
    zone_link,
    () => cursor_input_state_json(viewer, model),
    (line, column) => viewer.set_position(Position(line, column)),
    (anchor_line, anchor_column, active_line, active_column) => {
      viewer.set_selection(
        Selection(
          Position(anchor_line, anchor_column),
          Position(active_line, active_column),
        ),
      )
    },
    height => {
      host.set_attribute("style", "height:\{height}px;width:260px;")
      viewer.layout()
    },
    () => viewer.set_scroll_top(viewer.get_scroll_height()),
    () => viewer.focus(),
  )
}

///|
extern "js" fn record_cursor_content_event(version_id : Int) -> Unit =
  #| (versionId) => {
  #|   (globalThis.__cursorInputEventLog ??= []).push({
  #|     type: 'content',
  #|     versionId,
  #|   });
  #| }

///|
extern "js" fn record_cursor_event(event_json : String) -> Unit =
  #| (eventJson) => {
  #|   (globalThis.__cursorInputEventLog ??= []).push(JSON.parse(eventJson));
  #| }

///|
extern "js" fn install_cursor_input_controls(
  root : @rdom.Element,
  zone_text : @rdom.Element,
  zone_link : @rdom.Element,
  state_json : () -> String,
  set_position : (Int, Int) -> Unit,
  set_selection : (Int, Int, Int, Int) -> Unit,
  resize : (Int) -> Unit,
  show_zone : () -> Unit,
  focus : () -> Unit,
) -> Unit =
  #| (root, zoneText, zoneLink, stateJson, setPosition, setSelection, resize, showZone, focus) => {
  #|   globalThis.__cursorInputEventLog = [];
  #|   const keyLog = [];
  #|   const propagationLog = [];
  #|   const focusLog = [];
  #|   const pointerLog = [];
  #|   const copyLog = [];
  #|   let zoneLinkActivations = 0;
  #|   root.addEventListener('keydown', (event) => {
  #|     keyLog.push({
  #|       key: event.key,
  #|       altKey: event.altKey,
  #|       ctrlKey: event.ctrlKey,
  #|       metaKey: event.metaKey,
  #|       shiftKey: event.shiftKey,
  #|       defaultPrevented: event.defaultPrevented,
  #|       activeIsRoot: document.activeElement === root,
  #|     });
  #|   });
  #|   document.addEventListener('keydown', (event) => {
  #|     if (root.contains(event.target)) {
  #|       propagationLog.push({
  #|         key: event.key,
  #|         defaultPrevented: event.defaultPrevented,
  #|       });
  #|     }
  #|   });
  #|   root.addEventListener('focusin', (event) => {
  #|     focusLog.push({ type: 'focusin', targetClass: event.target?.className ?? '' });
  #|   });
  #|   root.addEventListener('focusout', (event) => {
  #|     focusLog.push({ type: 'focusout', targetClass: event.target?.className ?? '' });
  #|   });
  #|   for (const type of ['mousedown', 'mouseup']) {
  #|     root.addEventListener(type, (event) => {
  #|       pointerLog.push({
  #|         type,
  #|         detail: event.detail,
  #|         shiftKey: event.shiftKey,
  #|         defaultPrevented: event.defaultPrevented,
  #|       });
  #|     });
  #|   }
  #|   root.addEventListener('copy', (event) => {
  #|     copyLog.push({
  #|       defaultPrevented: event.defaultPrevented,
  #|       targetClass: event.target?.className ?? '',
  #|       nativeSelection: document.getSelection()?.toString() ?? '',
  #|       plain: event.clipboardData?.getData('text/plain') ?? '',
  #|       html: event.clipboardData?.getData('text/html') ?? '',
  #|     });
  #|   });
  #|   zoneLink.addEventListener('click', (event) => {
  #|     event.preventDefault();
  #|     zoneLinkActivations += 1;
  #|   });
  #|   globalThis.__cursorInputControls = {
  #|     state: () => JSON.parse(stateJson()),
  #|     events: () => [...globalThis.__cursorInputEventLog],
  #|     keys: () => [...keyLog],
  #|     propagation: () => [...propagationLog],
  #|     focus_events: () => [...focusLog],
  #|     pointers: () => [...pointerLog],
  #|     copies: () => [...copyLog],
  #|     copied_payload: () => {
  #|       const latest = copyLog.at(-1);
  #|       return { plain: latest?.plain ?? '', html: latest?.html ?? '' };
  #|     },
  #|     reset_copy: () => {
  #|       copyLog.length = 0;
  #|     },
  #|     select_zone_text: () => {
  #|       focus();
  #|       const selection = document.getSelection();
  #|       const range = document.createRange();
  #|       range.selectNodeContents(zoneText);
  #|       selection.removeAllRanges();
  #|       selection.addRange(range);
  #|       return {
  #|         text: selection.toString(),
  #|         activeIsRoot: document.activeElement === root,
  #|       };
  #|     },
  #|     clear_native_selection: () => document.getSelection()?.removeAllRanges(),
  #|     focus_zone_link: () => {
  #|       zoneLink.focus();
  #|       return document.activeElement === zoneLink;
  #|     },
  #|     zone_link_activations: () => zoneLinkActivations,
  #|     clear: () => {
  #|       globalThis.__cursorInputEventLog.length = 0;
  #|       keyLog.length = 0;
  #|       propagationLog.length = 0;
  #|       focusLog.length = 0;
  #|       pointerLog.length = 0;
  #|       copyLog.length = 0;
  #|     },
  #|     set_position: setPosition,
  #|     set_selection: setSelection,
  #|     resize,
  #|     show_zone: showZone,
  #|     focus,
  #|     root,
  #|   };
  #| }
