///|
/// Host-owned DOM remains outside the editor. Chromium owns resize, focus and
/// wheel input; the public DiffEditor owns anchoring and matching pane spacers.
pub fn run_diff_line_widgets_test() -> Unit {
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    abort("missing browser scenario mount")
  }
  let surface = document.create_element("div")
  surface.set_attribute("style", "position:relative;width:900px;height:420px")
  app.append_child(surface.as_node())
  let host = document.create_element("div")
  host.set_attribute("id", "line-widget-editor")
  host.set_attribute("style", "width:100%;height:100%")
  surface.append_child(host.as_node())
  let overlay = document.create_element("div")
  overlay.set_attribute(
    "style", "position:absolute;inset:0;overflow:hidden;pointer-events:none;z-index:12",
  )
  surface.append_child(overlay.as_node())
  let editor = @viewer.DiffEditor::create(
    host,
    options=DiffEditorOptions(automatic_inline=false),
  )
  let tail = "shared tail\n" + "unchanged\n".repeat(80)
  let original = diff_editor_lifecycle_model(
    "widget-original",
    "header\nold one\nold two\n" + tail,
  )
  let modified = diff_editor_lifecycle_model(
    "widget-modified",
    "header\nnew\n" + tail,
  )
  editor.set_model(Some(DiffEditorModel(original, modified))) |> ignore
  let widgets : Array[@viewer.DiffLineWidget] = []
  for (original, line, id) in [(true, 3, "old-card"), (false, 2, "new-card")] {
    let card = document.create_element(
      if original {
        "textarea"
      } else {
        "div"
      },
    )
    card.set_attribute("id", id)
    card.set_attribute(
      "style", "position:absolute;visibility:hidden;pointer-events:auto;background:#eef;border:1px solid #abc;box-sizing:border-box;padding:8px",
    )
    if original {
      card.set_attribute("aria-label", id)
      @base_browser.set_style_property(card, "height", "100px")
    } else {
      let label = document.create_element("div")
      label.append_child(document.create_text_node(id).as_node())
      card.append_child(label.as_node())
      let input = document.create_element("textarea")
      input.set_attribute("aria-label", id)
      input.set_attribute(
        "style", "width:100%;height:60px;box-sizing:border-box",
      )
      card.append_child(input.as_node())
    }
    overlay.append_child(card.as_node())
    widgets.push({
      original,
      line,
      node: card,
      on_layout: layout => {
        let rect = surface.get_bounding_client_rect()
        guard layout is Some((left, top, width)) else {
          @base_browser.set_style_property(card, "visibility", "hidden")
          return
        }
        @base_browser.set_style_property(card, "visibility", "visible")
        @base_browser.set_style_property(
          card,
          "left",
          "\{left - rect.get_left()}px",
        )
        @base_browser.set_style_property(
          card,
          "top",
          "\{top - rect.get_top()}px",
        )
        @base_browser.set_style_property(card, "width", "\{width}px")
      },
    })
  }
  editor.set_line_widgets(widgets)
  let line_action = (original, line) => {
    host.set_attribute("data-action", "\{original}:\{line}")
  }
  editor.set_line_action(Some(line_action))
  install_line_widget_controls(
    enabled => {
      editor.set_line_action(if enabled { Some(line_action) } else { None })
    },
    (original, line) => {
      editor.set_line_action(Some(line_action), allowed=(side, target) => {
        side == original && target == line
      })
    },
    inline => {
      editor.update_options(
        DiffEditorOptions(
          layout=if inline { Inline } else { SideBySide },
          automatic_inline=false,
        ),
      )
    },
    () => editor.set_line_widgets(widgets),
    old => {
      if old {
        original.set_value("prefix\nheader\nold one\nold two\n" + tail)
      } else {
        modified.set_value("prefix\nheader\nnew\n" + tail)
      }
    },
    () => editor.is_diff_up_to_date(),
    () => editor.set_model(None) |> ignore,
    () => {
      editor.dispose()
      original.dispose()
      modified.dispose()
    },
  )
}

///|
extern "js" fn install_line_widget_controls(
  action : (Bool) -> Unit,
  restrict : (Bool, Int) -> Unit,
  layout : (Bool) -> Unit,
  refresh : () -> Unit,
  edit : (Bool) -> Unit,
  ready : () -> Bool,
  clear : () -> Unit,
  dispose : () -> Unit,
) -> Unit =
  #| (action, restrict, layout, refresh, edit, ready, clear, dispose) => {
  #|   globalThis.__lineWidgets = { action, restrict, layout, refresh, edit, ready, clear, dispose };
  #| }
