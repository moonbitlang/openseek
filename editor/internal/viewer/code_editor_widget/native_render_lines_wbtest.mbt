///|
extern "js" fn install_native_render_lines_test_dom() -> Unit =
  #| () => {
  #|   globalThis.__nativeRenderLinesOriginalDocument = globalThis.document;
  #|   class TestElement {
  #|     constructor(tag) {
  #|       this.tagName = String(tag).toUpperCase();
  #|       this.attributes = new Map();
  #|       this._innerHTML = "";
  #|       this.style = {
  #|         setProperty(name, value) { this[name] = String(value); },
  #|       };
  #|     }
  #|     setAttribute(name, value) {
  #|       this.attributes.set(String(name), String(value));
  #|     }
  #|     getAttribute(name) {
  #|       return this.attributes.has(String(name))
  #|         ? this.attributes.get(String(name))
  #|         : null;
  #|     }
  #|     removeAttribute(name) { this.attributes.delete(String(name)); }
  #|     set innerHTML(value) { this._innerHTML = String(value); }
  #|     get innerHTML() { return this._innerHTML; }
  #|   }
  #|   globalThis.document = {
  #|     createElement(tag) { return new TestElement(tag); },
  #|   };
  #| }

///|
extern "js" fn restore_native_render_lines_test_dom() -> Unit =
  #| () => {
  #|   globalThis.document = globalThis.__nativeRenderLinesOriginalDocument;
  #|   delete globalThis.__nativeRenderLinesOriginalDocument;
  #| }

///|
extern "js" fn native_render_lines_test_html(element : @rdom.Element) -> String = "(element) => element.innerHTML"

///|
fn with_native_render_lines_test_dom(body : () -> Unit raise) -> Unit raise {
  install_native_render_lines_test_dom()
  defer restore_native_render_lines_test_dom()
  body()
}

///|
test "native render_lines applies the display limit without truncating its model" {
  let text = "x".repeat(10001) + "END"
  let source = test_model(text, language_id="plaintext")
  defer source.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget()
  defer viewer.dispose()
  with_native_render_lines_test_dom(() => {
    let bounded = viewer.render_lines(source, LineRange(1, 2)).unwrap()
    let html = native_render_lines_test_html(bounded.dom_node())
    assert_true(html.contains("mtkoverflow"))
    assert_false(html.contains("END"))
    assert_eq(source.get_value(), text)
    viewer.update_host_options(
      CodeEditorOptions(line_rendering_limit=Unlimited),
    )
    let full = viewer.render_lines(source, LineRange(1, 2)).unwrap()
    assert_true(native_render_lines_test_html(full.dom_node()).contains("END"))
  })
}

///|
test "native render_lines keeps tokenizer spans and UTF-16 decorations" {
  let viewer = CodeEditorWidget::CodeEditorWidget(
    options=CodeEditorOptions(font_size=12, line_height=18),
  )
  defer viewer.dispose()
  let source = test_model("let old = \"😀\"", language_id="plaintext")
  defer source.dispose()
  viewer.set_model(Some(source))
  viewer.test_set_viewport(width=800.0, height=180.0)
  viewer.test_view_model().visible_lines_stabilized()
  with_native_render_lines_test_dom(() => {
    let rendered = viewer
      .render_lines(
        source,
        LineRange(1, 2),
        decorations=[
          {
            range: Range(1, 5, 1, 8),
            class_name: "diff-editor-inline-char-delete",
          },
        ],
        line_class_name="diff-editor-inline-deleted-line",
      )
      .unwrap()
    let html = native_render_lines_test_html(rendered.dom_node())
    assert_true(html.contains("<span class=\"mtk1\">"))
    assert_true(
      html.contains(
        "<span class=\"mtk1 diff-editor-inline-char-delete\">old</span>",
      ),
    )
    assert_true(html.contains("😀"))
    assert_eq(rendered.view_line_count(), 1)
    assert_true(rendered.model_line_view_counts() == [1])
  })
}

///|
test "native render_lines uses editor wrapping and exact model-line heights" {
  with_native_render_lines_test_dom(() => {
    let source = test_model("abcdefghij")
    defer source.dispose()
    let options = CodeEditorOptions(
      font_size=12,
      line_height=18,
      soft_wrap=true,
    )
    with_test_viewer(
      "host",
      viewer => {
        viewer.test_set_soft_wrap_column(6)
        let rendered = viewer.render_lines(source, LineRange(1, 2)).unwrap()
        assert_eq(rendered.view_line_count(), 2)
        assert_eq(rendered.height_in_px(), 36.0)
        assert_true(rendered.model_line_view_counts() == [2])
        let html = native_render_lines_test_html(rendered.dom_node())
        assert_true(html.contains("top:0px"))
        assert_true(html.contains("top:18px"))
      },
      options~,
    )
  })
}

///|
test "native render_lines can keep marker rows while suppressing numbers" {
  with_native_render_lines_test_dom(() => {
    let source = test_model("deleted\nrows")
    defer source.dispose()
    with_test_viewer("host", viewer => {
      let rendered = viewer
        .render_lines(
          source,
          LineRange(1, 3),
          margin_line_class_name="delete-sign codicon codicon-diff-remove",
          render_margin_line_numbers=false,
        )
        .unwrap()
      let html = native_render_lines_test_html(rendered.margin_dom_node())
      assert_true(html.contains("delete-sign codicon codicon-diff-remove"))
      assert_false(html.contains(">1</div>"))
      assert_false(html.contains(">2</div>"))
      assert_eq(rendered.view_line_count(), 2)
    })
  })
}

///|
test "native render_lines preserves tab CJK emoji and RTL source" {
  with_native_render_lines_test_dom(() => {
    let source = test_model("\t中😀 אבג")
    defer source.dispose()
    let options = CodeEditorOptions(font_size=12, line_height=18, tab_size=4)
    with_test_viewer(
      "host",
      viewer => {
        let rendered = viewer.render_lines(source, LineRange(1, 2)).unwrap()
        let html = native_render_lines_test_html(rendered.dom_node())
        assert_false(html.contains("\t"))
        assert_true(html.contains("中"))
        assert_true(html.contains("😀"))
        assert_true(html.contains("אבג"))
        assert_true(html.contains(" dir=\""))
        assert_true(rendered.min_width_in_px() > 16.0)
      },
      options~,
    )
  })
}

///|
test "native render_lines does not truncate a very long source line" {
  with_native_render_lines_test_dom(() => {
    let source_text = "x".repeat(2600) + "END"
    let source = test_model(source_text)
    defer source.dispose()
    with_test_viewer("host", viewer => {
      let rendered = viewer.render_lines(source, LineRange(1, 2)).unwrap()
      let html = native_render_lines_test_html(rendered.dom_node())
      assert_true(html.contains("END"))
      assert_true(html.length() > 2600)
      assert_true(rendered.min_width_in_px() > 1000.0)
      assert_eq(rendered.view_line_count(), 1)
    })
  })
}
