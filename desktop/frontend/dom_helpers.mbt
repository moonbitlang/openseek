///|
/// Bring the sidebar's active project row into view on the render that
/// applies it: the row a fresh add just activated can sit below the fold
/// of a long sidebar. `nearest` keeps everything still when the row is
/// already visible.
fn reveal_active_project() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().query_selector(".workspace-row.active").to_option()
        is Some(row) {
        row.scroll_into_view_with_options(block="nearest")
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// The media-query list for the host's dark-mode preference, or `None` in a
/// webview without `matchMedia`.
fn color_scheme_query() -> @js.Value? {
  guard @interop.js_prop(@js.globalThis, "matchMedia") is Some(_) else {
    return None
  }
  Some(
    @js.globalThis.apply_with_string("matchMedia", [
      @js.Value::cast_from("(prefers-color-scheme: dark)"),
    ]),
  )
}

///|
/// Whether the host prefers a dark color scheme, read once at startup
/// (`initial_model`) and kept fresh by `watch_color_scheme`. The app's own
/// palette flips via the `prefers-color-scheme` media query in CSS; this
/// mirror of it drives the embedded viewer's `data-theme`, which CSS cannot
/// reach.
fn host_prefers_dark() -> Bool {
  guard color_scheme_query() is Some(query) else { return false }
  (@js.Cast::into(query.get_with_string("matches")) : Bool?) is Some(true)
}

///|
/// Mirror the effective model theme onto the document root after update. CSS
/// owns the palette; the command keeps the DOM write out of the pure handler.
fn Theme::apply(
  self : Theme,
  system_dark : Bool,
  is_desktop : Bool,
  dispatch : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  let value = if self.is_dark(system_dark) { "dark" } else { "light" }
  @cmd.batch([
    @cmd.custom_cmd(_ => {
      if @dom.document().get_document_element() is Some(root) {
        root.set_attribute("data-theme", value)
      }
    }),
    if is_desktop {
      app_set_titlebar_theme(dispatch, value == "dark")
    } else {
      @cmd.none
    },
    @fileeditor.apply_theme(value),
  ])
}

///|
/// Apply one monospace choice to CSS code surfaces and both imperative text
/// widgets. The editor and terminal commands also update their measured font
/// state and existing DOM.
fn AppFont::apply(self : AppFont) -> @cmd.Cmd {
  let wire = self.wire()
  let family = self.css_family()
  @cmd.batch([
    @cmd.custom_cmd(_ => {
      if @dom.document().get_document_element() is Some(root) {
        root.set_attribute("data-font", wire)
      }
    }),
    @fileeditor.apply_font_family(family),
    @terminal.apply_font_family(family),
  ])
}

///|
/// Apply one type scale to CSS and both measured text widgets. The root token
/// changes ordinary app text; editor and terminal commands apply the visually
/// matched monospace size and recompute glyph geometry immediately.
fn AppFontSize::apply(self : AppFontSize) -> @cmd.Cmd {
  let wire = self.wire()
  let pixels = self.pixels()
  @cmd.batch([
    @cmd.custom_cmd(_ => {
      if @dom.document().get_document_element() is Some(root) {
        root.set_attribute("data-font-size", wire)
      }
    }),
    @fileeditor.apply_font_size(pixels),
    @terminal.apply_font_size(pixels),
  ])
}

///|
let color_scheme_watched : Ref[Bool] = Ref(false)

///|
/// Follow the host's dark-mode preference, feeding changes back as
/// `ColorSchemeChanged`. Update retains every report and applies it immediately
/// only while Settings remains on System.
fn watch_color_scheme(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard !color_scheme_watched.val else { return }
    guard color_scheme_query() is Some(query) else { return }
    color_scheme_watched.val = true
    @interop.add_capture_listener(query, "change", event => {
      let matches : @js.Value = @js.Cast::from(event).get_with_string("matches")
      scheduler.add(
        dispatch(
          ColorSchemeChanged((@js.Cast::into(matches) : Bool?) is Some(true)),
        ),
      )
    })
  })
}

///|
/// Write a custom property on the document element, where the stylesheets read
/// it. Going through CSSOM rather than the `style` attribute preserves the
/// properties other writers own (the sidebar's dragged width, the editor's).
fn set_root_custom_property(name : String, value : String) -> Unit {
  guard @dom.document().get_document_element() is Some(root) else { return }
  let style : @js.Value = @js.Value::cast_from(root).get_with_string("style")
  let _ : @js.Value = style.apply_with_string("setProperty", [
    @js.Value::cast_from(name),
    @js.Value::cast_from(value),
  ])
}

///|
/// The property `styles/sidebar.css` subtracts from its right inset.
const ScrollbarLaneProperty = "--scrollbar-lane"

///|
/// Side of the throwaway scroller the lane is measured with. Arbitrary — only
/// its difference from the client width is read.
const ScrollbarProbeSide = 100

///|
/// Measure how much width a scrolling pane loses to its scrollbar and publish
/// it as `--scrollbar-lane`. macOS draws overlay scrollbars, which float above
/// the content and reserve nothing — `scrollbar-gutter: stable` leaves such a
/// pane's edge flush; Windows and Linux draw classic ones, which take a lane
/// out of the box. Nothing in CSS tells the two apart, and neither does the
/// platform: macOS switches to classic bars under System Settings › Appearance
/// › "Show scroll bars: Always". So measure a throwaway scroller and hand CSS
/// the number. Read once at startup, which is also when a change to that
/// system preference is picked up.
fn measure_scrollbar_lane() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    guard @dom.document().get_body() is Some(body) else { return }
    let probe = @dom.document().create_element("div")
    // Inline styles, so no stylesheet can reshape the probe. `overflow-y:
    // scroll` rather than `auto` puts a classic bar there even though the
    // probe has nothing to scroll; the scrollbar's own styling is inherited
    // from the document, so the probe sees whatever the real panes see.
    probe.set_attribute(
      "style",
      "position:absolute;top:-9999px;left:-9999px;border:0;padding:0;" +
      "width:\{ScrollbarProbeSide}px;height:\{ScrollbarProbeSide}px;overflow-y:scroll",
    )
    let node = probe.as_node()
    body.append_child(node)
    let lane = (ScrollbarProbeSide.to_double() - probe.get_client_width()).to_int()
    body.remove_child(node)
    set_root_custom_property(ScrollbarLaneProperty, "\{lane}px")
  })
}
