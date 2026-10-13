// Pins the per-model `View` lifecycle across `set_model` (Monaco's
// `setModel` → `_detachModel` → `_attachModel`, `codeEditorWidget.ts:506`):
// the old view's DOM subtree leaves the container, exactly one editor root
// exists per attached model, `data-uri` / `data-mode-id` are stamped,
// model-scoped view zones are lost with the old view, text focus carries
// across the swap (`cew:528-532`), and detaching to no model restores the
// Viewer-owned placeholder.

///|
/// Whether the document's active element is the given selector's first
/// match (no `document.activeElement` binding in the vendored `@rdom`).
extern "js" fn active_element_matches(selector : String) -> Bool =
  #| (selector) => {
  #|   const el = document.querySelector(selector);
  #|   return !!el && document.activeElement === el;
  #| }

///|
/// Pauses the MoonBit-side scenario at a visible browser state so Playwright
/// can create the persistent hover widget before the swap, then exercise its
/// scrollbar after the new per-View MouseHandler is installed.
extern "js" fn install_model_swap_continue(
  phase : String,
  callback : () -> Unit,
) -> Unit =
  #| (phase, callback) => {
  #|   globalThis.__modelSwapPhase = phase;
  #|   globalThis.__modelSwapContinue = () => {
  #|     globalThis.__modelSwapPhase = "continuing";
  #|     delete globalThis.__modelSwapContinue;
  #|     callback();
  #|   };
  #| }

///|
fn swap_model(name : String, marker : String) -> @model.TextModel {
  let lines = StringBuilder()
  lines.write_string(marker)
  for index in 1..<40 {
    lines.write_char('\n')
    lines <+ "line_\{index}_of_\{name}"
  }
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/\{name}",
    ),
    name,
    "plaintext",
    1,
    "swap-rev-\{name}",
    lines.to_string(),
  )
}

///|
fn seed_swap_diagnostic(
  markers : @markers.MarkerService,
  model : @model.TextModel,
) -> Unit {
  markers.set_diagnostics("swap", model.uri, [
    {
      range: Range(1, 1, 1, 6),
      severity: Error,
      message: "persistent hover diagnostic",
      tags: None,
    },
  ])
}

///|
pub fn run_model_swap_test() -> Unit {
  let ctx = @support.BrowserTestContext("model_swap")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host")
  host.set_attribute("style", "height:200px;width:400px;")
  app.append_child(host.as_node())
  let placeholder_host = document.create_element("div")
  placeholder_host.set_attribute("class", "placeholder-host")
  placeholder_host.set_attribute("style", "height:80px;width:300px;")
  app.append_child(placeholder_host.as_node())
  let placeholder_viewer = @viewer.Viewer::create(
    placeholder_host,
    options=ViewerOptions(placeholder="dispose-placeholder"),
  )
  let markers = @markers.MarkerService(schedule=model_swap_queue_microtask)
  let services = @viewer.ViewerServices(
    markers=MarkerStore(markers.marker_service_handle()),
  )
  let viewer = @viewer.Viewer::create(
    host,
    services~,
    options=ViewerOptions(placeholder="swap-placeholder"),
  )
  let model_a = swap_model("swap-a.txt", "alpha_document_marker")
  let model_b = swap_model("swap-b.txt", "beta_document_marker")
  let model_c = swap_model("swap-c.txt", "gamma_document_marker")
  seed_swap_diagnostic(markers, model_a)
  seed_swap_diagnostic(markers, model_b)
  let first_overlay_node = document.create_element("div")
  first_overlay_node.set_attribute("class", "swap-overlay-first")
  let second_overlay_node = document.create_element("div")
  second_overlay_node.set_attribute("class", "swap-overlay-second")
  let unknown_overlay_node = document.create_element("div")
  unknown_overlay_node.set_attribute("class", "swap-overlay-unknown")
  let stale_overlay = @viewer.overlay_widget("swap-overlay", first_overlay_node)
  let current_overlay = @viewer.overlay_widget(
    "swap-overlay", second_overlay_node,
  )
  let unknown_overlay = @viewer.overlay_widget(
    "unknown-swap-overlay", unknown_overlay_node,
  )
  viewer.set_model(Some(model_a))
  viewer.handle_initialized()
  viewer.add_overlay_widget(stale_overlay)
  viewer.add_overlay_widget(current_overlay)
  ctx.assert_true(
    @support.query_count(".swap-overlay-first") == 0 &&
    @support.query_count(".swap-overlay-second") == 1,
    "duplicate overlay id did not keep the last writer",
  )
  viewer.remove_overlay_widget(stale_overlay)
  ctx.assert_true(
    @support.query_count(".swap-overlay-second") == 0,
    "stale overlay handle did not remove the current id registration",
  )
  viewer.add_overlay_widget(current_overlay)
  viewer.remove_overlay_widget(unknown_overlay)
  ctx.assert_true(
    @support.query_count(".swap-overlay-second") == 1 &&
    @support.query_count(".swap-overlay-unknown") == 0,
    "unknown overlay removal changed the live registration",
  )
  viewer.focus()
  let zone = document.create_element("div")
  zone.set_attribute("class", "swap-zone")
  zone.set_inner_html("swap view zone")
  viewer.change_view_zones(accessor => {
    accessor.add_zone(@viewer.view_zone(1, zone, height_in_px=24.0)) |> ignore
  })
  wait_for_text(ctx, "alpha_document_marker", 80, () => {
    // One editor root per attached model; the placeholder left the container.
    ctx.assert_true(
      @support.query_count(".viewer-host > .monaco-editor") == 1,
      "expected exactly one editor root for model A",
    )
    ctx.assert_true(
      @support.query_attribute(".viewer-host > .monaco-editor", "data-uri") ==
      Some(model_a.uri.to_string()),
      "data-uri not stamped for model A",
    )
    ctx.assert_true(
      @support.query_attribute(".viewer-host", "data-mode-id") ==
      Some("plaintext"),
      "data-mode-id not stamped on the container",
    )
    ctx.assert_true(
      @support.query_count(".swap-zone[monaco-view-zone]") == 1,
      "view zone missing on the first view",
    )
    ctx.assert_true(
      @support.query_count(".swap-overlay-second") == 1 &&
      @support.query_attribute(".swap-overlay-second", "widgetId") ==
      Some("swap-overlay"),
      "overlay widget missing or unstamped on model A",
    )
    install_model_swap_continue("model-a", () => {
      // Swap: the whole view is rebuilt (Monaco's detach-then-attach).
      viewer.set_model(Some(model_b))
      viewer.handle_initialized()
      model_a.dispose()
      wait_for_text(ctx, "beta_document_marker", 80, () => {
        ctx.assert_true(
          @support.query_count(".viewer-host > .monaco-editor") == 1,
          "old view DOM survived the swap",
        )
        ctx.assert_true(
          @support.query_attribute(".viewer-host > .monaco-editor", "data-uri") ==
          Some(model_b.uri.to_string()),
          "data-uri not restamped for model B",
        )
        ctx.assert_true(
          @support.query_count(".swap-zone[monaco-view-zone]") == 0,
          "model-scoped view zone survived onto the new view",
        )
        ctx.assert_true(
          @support.query_count(".swap-overlay-second") == 1,
          "viewer-scoped overlay widget was not replayed on model B",
        )
        // Text focus carries across the swap (`cew:528-532`).
        ctx.assert_true(
          viewer.has_text_focus(),
          "editor lost text focus across the swap",
        )
        ctx.assert_true(
          active_element_matches(".viewer-host > .monaco-editor"),
          "DOM focus is not on the new view root",
        )
        install_model_swap_continue("model-b", () => {
          // Detach to no model: the Viewer-owned placeholder returns.
          viewer.set_model(None)
          model_b.dispose()
          wait_for_text(ctx, "swap-placeholder", 80, () => {
            ctx.assert_true(
              @support.query_count(".viewer-host > .monaco-editor.source-empty") ==
              1,
              "placeholder did not return after detach",
            )
            ctx.assert_true(
              @support.query_count(".viewer-host [data-uri]") == 0,
              "a per-model view survived the detach",
            )
            ctx.assert_true(
              @support.query_attribute(".viewer-host", "data-mode-id") is None,
              "data-mode-id survived the detach",
            )
            ctx.assert_true(
              viewer.has_text_focus() == false,
              "editor still reports text focus with no model",
            )
            ctx.assert_true(
              @support.query_count(".swap-overlay-second") == 0,
              "overlay widget remained mounted with no model",
            )
            // Reattach once so Viewer.dispose itself tears down a real View (the
            // preceding None transition already covered ordinary placeholder
            // restoration). Queue a root render and dispose before it can run.
            viewer.set_model(Some(model_c))
            viewer.handle_initialized()
            wait_for_text(ctx, "gamma_document_marker", 80, () => {
              ctx.assert_true(
                @support.query_count(".swap-overlay-second") == 1,
                "overlay widget was not replayed after reattach",
              )
              install_model_swap_continue("model-c", () => {
                // A second Viewer exercises the disposal path while its no-model
                // placeholder is still mounted, with a pending placeholder frame.
                placeholder_viewer.layout()
                placeholder_viewer.dispose()
                placeholder_viewer.dispose()
                viewer.layout()
                viewer.dispose()
                viewer.dispose()
                ctx.assert_true(
                  @support.query_count(".viewer-host") == 1,
                  "Viewer disposal removed the caller-owned host",
                )
                ctx.assert_true(
                  @support.query_count(".viewer-host > .monaco-editor") == 0,
                  "Viewer-owned DOM survived disposal",
                )
                ctx.assert_true(
                  @support.query_count(".placeholder-host") == 1 &&
                  @support.query_count(".placeholder-host > .monaco-editor") ==
                  0,
                  "placeholder DOM survived disposal or its host was removed",
                )
                ctx.assert_true(
                  !model_c.is_disposed(),
                  "Viewer disposal disposed the caller-owned model",
                )
                ctx.assert_true(
                  @support.query_count(".swap-overlay-second") == 0 &&
                  second_overlay_node.get_attribute("widgetId") ==
                  Some("swap-overlay"),
                  "Viewer disposal kept the overlay mounted or destroyed its node",
                )
                model_c.dispose()
                // The bundle owns the decorations adapter and default feedback
                // store; dispose it after its subscriptions leave the marker store.
                services.dispose()
                markers.dispose()
                ctx.finish()
              })
            })
          })
        })
      })
    })
  })
}

///|
/// Preserve the browser scheduling used by the default Viewer marker store
/// while keeping the concrete backing in this scenario's ownership scope.
extern "js" fn model_swap_queue_microtask(callback : () -> Unit) -> Unit =
  #| (callback) => globalThis.queueMicrotask(callback)

///|
/// Polls until the editor surface contains `needle`, then runs `body`.
fn wait_for_text(
  ctx : @support.BrowserTestContext,
  needle : String,
  remaining : Int32,
  body : () -> Unit,
) -> Unit {
  if @support.query_text(".viewer-host") is Some(text) && text.contains(needle) {
    body()
    return
  }
  if remaining <= 0 {
    let saw = match @support.query_text(".viewer-host") {
      Some(text) => text
      None => "<missing viewer host>"
    }
    ctx.fail("timed out waiting for text: \{needle} (saw: \{saw})")
    ctx.finish()
    return
  }
  @support.set_timeout(
    () => wait_for_text(ctx, needle, remaining - 1, body),
    50,
  )
}
