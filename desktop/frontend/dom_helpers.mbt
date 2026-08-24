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
fn Theme::apply(self : Theme, system_dark : Bool) -> @cmd.Cmd {
  let value = if self.is_dark(system_dark) { "dark" } else { "light" }
  @cmd.batch([
    @cmd.custom_cmd(_ => {
      if @dom.document().get_document_element() is Some(root) {
        root.set_attribute("data-theme", value)
      }
    }),
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
