///|
priv struct ComponentHoverProvider {
  hover_text : String
}

///|
fn ComponentHoverProvider::new() -> ComponentHoverProvider {
  { hover_text: "wrapped component hover", }
}

///|
impl @language.HoverProvider for ComponentHoverProvider with fn provide_hover(
  self,
  model,
  position,
  _token,
) {
  let needle = "keeps"
  let offset = model.get_offset_at(position)
  match model.snapshot.get_value().find(needle) {
    Some(start) =>
      if offset >= start && offset < start + needle.length() {
        Some({
          range: model.snapshot.range_of(
            OffsetRange(start, start + needle.length()),
          ),
          contents: [PlainText(self.hover_text)],
        })
      } else {
        None
      }
    None => None
  }
}

///|
/// Diagnostics are push-only: the embedder feeds the marker service directly
/// (Monaco's `setModelMarkers`), and the marker-change event drives the
/// squiggle render.
fn set_component_diagnostics(
  markers : @markers.MarkerService,
  model : @model.TextModel,
) -> Unit {
  let needle = "keeps"
  if model.snapshot.get_value().find(needle) is Some(start) {
    markers.set_diagnostics("lsp", model.uri, [
      {
        range: model.snapshot.range_of(
          OffsetRange(start, start + needle.length()),
        ),
        severity: Warning,
        message: "wrapped component diagnostic",
        tags: None,
      },
    ])
  }
}

///|
fn run_viewer_api_test() -> Unit {
  let ctx = @support.BrowserTestContext("viewer_api")
  assert_container_contract(ctx)
  let rendered_count = Ref(0)
  let rendered_line_count = Ref(0)
  let view_line_count = Ref(0)
  let done = Ref(false)
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/component.mbt",
  )
  let model = @model.TextModel(
    uri,
    "component.mbt",
    "moonbit",
    1,
    "component-rev-1",
    component_source_text(),
  )
  let model_line_count = component_model_line_count()
  match mount_host() {
    Some(host) => {
      let log_service = @log.LogService()
      let log_handle = log_service.log_handle()
      let languages = @languages.Languages()
      let markers = @markers.MarkerService(schedule=component_queue_microtask)
      let services = @viewer.ViewerServices(
        languages=languages.language_handle(log_handle),
        markers=MarkerStore(markers.marker_service_handle()),
        log_service=log_handle,
      )
      languages.set_tokens_provider("moonbit", @lang_moonbit.MoonBitTokenizer())
      |> ignore
      let provider = ComponentHoverProvider::new()
      languages.register_hover_provider(LanguageId("moonbit"), provider)
      |> ignore
      let viewer = @viewer.Viewer::create(
        host,
        services~,
        options=ViewerOptions(
          soft_wrap=true,
          smooth_scrolling=true,
          placeholder="Loading component fixture...",
        ),
      )
      let scroll_event_count = Ref(0)
      viewer.on_did_scroll_change(event => {
        scroll_event_count.val += 1
        host.set_attribute(
          "data-scroll-events",
          scroll_event_count.val.to_string(),
        )
        host.set_attribute("data-scroll-top", event.scroll_top.to_string())
      })
      |> ignore
      @viewer_testing.on_did_render_model(viewer.get_id(), event => {
        if event.fresh {
          rendered_count.val += 1
          view_line_count.val = event.line_count
          rendered_line_count.val = event.rendered_lines
        }
      })
      |> ignore
      viewer.set_model(Some(model))
      viewer.handle_initialized()
      set_component_diagnostics(markers, model)
      let zone = @rdom.document().create_element("div")
      zone.set_attribute("class", "component-zone host-zone-class")
      zone.set_attribute("style", "color: rgb(1, 2, 3);")
      zone.set_inner_html("component view zone")
      viewer.change_view_zones(accessor => {
        // Monaco's public delegate anchors in model space. Column 23 is the
        // wrap boundary after `component_answe`, so it converts to view line
        // 3 and keeps the zone directly above the `r : T() -> Int {` segment
        // the spec measures against.
        accessor.add_zone(
          @viewer.view_zone(2, zone, after_column=23, height_in_px=36.0),
        )
        |> ignore
      })
      @support.set_timeout(
        () => {
          poll_rendered(
            ctx, rendered_count, rendered_line_count, view_line_count, model_line_count,
            done, 80,
          )
        },
        50,
      )
    }
    None => {
      ctx.fail("missing #app mount point")
      ctx.finish()
    }
  }
}

///|
/// Public construction always retains the exact caller host, while the
/// model/view DOM query remains nullable before attachment and after disposal.
fn assert_container_contract(ctx : @support.BrowserTestContext) -> Unit {
  let host = @rdom.document().create_element("div")
  let viewer = @viewer.Viewer::create(host)
  ctx.assert_true(
    viewer.get_container_dom_node().as_node().is_same_node(host.as_node()),
    "get_container_dom_node did not return the construction host",
  )
  ctx.assert_true(
    viewer.get_dom_node() is None,
    "get_dom_node should be empty without a model view",
  )
  viewer.dispose()
  ctx.assert_true(
    viewer.get_container_dom_node().as_node().is_same_node(host.as_node()),
    "dispose forgot the original construction host",
  )
  ctx.assert_true(
    viewer.get_dom_node() is None,
    "get_dom_node should remain empty after disposal",
  )
}

///|
/// Keep caller-owned marker delivery on the same browser microtask cadence as
/// ViewerServices' built-in marker store.
extern "js" fn component_queue_microtask(callback : () -> Unit) -> Unit =
  #| (callback) => globalThis.queueMicrotask(callback)

///|
fn mount_host() -> @rdom.Element? {
  let document = @rdom.document()
  match document.query_selector("#app").to_option() {
    Some(app) => {
      let shell = document.create_element("main")
      shell.set_attribute("class", "editor-shell")
      shell.set_attribute("data-theme", "dark")
      shell.set_attribute("style", "height:100vh;display:block;")
      let host = document.create_element("div")
      host.set_attribute("class", "viewer-host")
      host.set_attribute("style", "height:180px;width:180px;")
      shell.append_child(host.as_node())
      app.append_child(shell.as_node())
      Some(host)
    }
    None => None
  }
}

///|
fn poll_rendered(
  ctx : @support.BrowserTestContext,
  rendered_count : Ref[Int],
  rendered_lines : Ref[Int],
  view_lines : Ref[Int],
  model_lines : Int,
  done : Ref[Bool],
  remaining : Int,
) -> Unit {
  if done.val {
    return
  }
  let text = @support.query_text(".monaco-editor.readonly-editor")
  // Grammar tokenization may complete on the bounded background scheduler
  // after the first default-token paint. Wait for the token-driven repaint,
  // rather than treating the intentionally passive first read as final.
  let has_keyword_tokens = @support.query_count(".mtk3") > 0
  if text.contains("component_answer") && has_keyword_tokens {
    ctx.assert_true(
      rendered_count.val > 0,
      "viewer did not emit a rendered notification",
    )
    ctx.assert_true(rendered_lines.val > 0, "viewer rendered no lines")
    ctx.assert_true(
      view_lines.val > model_lines,
      "soft wrap did not project additional view lines",
    )
    ctx.assert_true(
      @support.query_count(".monaco-editor.readonly-editor .view-line") > 0,
      "viewer did not create rendered line DOM",
    )
    ctx.assert_true(
      @support.query_attribute(".monaco-editor.readonly-editor", "data-theme") ==
      "dark",
      "viewer did not mirror the dark theme onto its root",
    )
    // Monaco's `LineNumbersOverlay`: a number renders only on a model line's
    // first view line, so soft-wrap continuations thin the count below the
    // rendered view lines (never above).
    ctx.assert_true(
      @support.query_count(".margin-view-overlays .line-numbers") > 0 &&
      @support.query_count(".margin-view-overlays .line-numbers") <=
      @support.query_count(".monaco-editor.readonly-editor .view-line"),
      "line numbers did not track model-line-starting view lines",
    )
    ctx.metric_int("renderedLines", rendered_lines.val)
    ctx.metric_int("viewLines", view_lines.val)
    ctx.metric_int("modelLines", model_lines)
    done.val = true
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for component_answer to render")
    done.val = true
    ctx.finish()
  } else {
    @support.set_timeout(
      () => {
        poll_rendered(
          ctx,
          rendered_count,
          rendered_lines,
          view_lines,
          model_lines,
          done,
          remaining - 1,
        )
      },
      50,
    )
  }
}

///|
fn component_source_text() -> String {
  (
    #|///|
    #|pub fn component_answer() -> Int {
    #|  let really_long_component_identifier_name = "component_answer keeps this line long enough to wrap"
    #|  really_long_component_identifier_name.length()
    #|}
    #|
  )
}

///|
fn component_model_line_count() -> Int {
  @model.TextSnapshot(component_source_text()).line_count()
}
