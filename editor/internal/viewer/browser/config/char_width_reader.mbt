// Ported from `vscode/src/vs/editor/browser/config/charWidthReader.ts`.
// Monaco's `DomCharWidthReader` class is construction ceremony around one
// synchronous read; `read_char_widths` keeps the source function's name
// and steps (build the test DOM, attach to `document.body`, read
// `offsetWidth / 256`, remove).

///|
#warnings("-unused_value")
priv enum CharWidthRequestType {
  Regular
  Italic
  Bold
} derive(Eq)

///|
priv struct CharWidthRequest {
  chr : String
  request_type : CharWidthRequestType
  mut width : Double
}

///|
fn CharWidthRequest::CharWidthRequest(
  chr : String,
  request_type : CharWidthRequestType,
) -> CharWidthRequest {
  { chr, request_type, width: 0.0, }
}

///|
fn CharWidthRequest::fulfill(self : CharWidthRequest, width : Double) -> Unit {
  self.width = width
}

///|
/// Monaco `readCharWidths`: measures every request's character in a
/// hidden container styled with the bare font info (regular, bold, and
/// italic test rows).
fn read_char_widths(
  bare_font_info : @common_config.BareFontInfo,
  requests : Array[CharWidthRequest],
) -> Unit {
  let document = @rdom.document()
  let container = document.create_element("div")
  container.set_attribute(
    "style", "position:absolute;top:-50000px;width:50000px",
  )
  let regular_dom_node = document.create_element("div")
  apply_font_info(regular_dom_node, bare_font_info)
  container.append_child(regular_dom_node.as_node())
  let bold_dom_node = document.create_element("div")
  apply_font_info(bold_dom_node, bare_font_info)
  @base_browser.set_style_property(bold_dom_node, "font-weight", "bold")
  container.append_child(bold_dom_node.as_node())
  let italic_dom_node = document.create_element("div")
  apply_font_info(italic_dom_node, bare_font_info)
  @base_browser.set_style_property(italic_dom_node, "font-style", "italic")
  container.append_child(italic_dom_node.as_node())
  let test_elements : Array[@rdom.Element] = []
  for request in requests {
    let parent = match request.request_type {
      Regular => regular_dom_node
      Bold => bold_dom_node
      Italic => italic_dom_node
    }
    parent.append_child(document.create_element("br").as_node())
    let test_element = document.create_element("span")
    // Repeat the character 256 (2^8) times; a space measures as NBSP so
    // the test span doesn't collapse.
    let chr = if request.chr == " " { "\u{a0}" } else { request.chr }
    let test_string = chr.repeat(256)
    test_element.append_child(document.create_text_node(test_string).as_node())
    parent.append_child(test_element.as_node())
    test_elements.push(test_element)
  }
  append_to_body(container)
  for index, request in requests {
    request.fulfill(
      @base_browser.element_offset_width(test_elements[index]) / 256.0,
    )
  }
  @base_browser.remove_element(container)
}

///|
/// FFI gap-fill for the current document body, which is not exposed by the
/// vendored `@rdom` document wrapper.
extern "js" fn append_to_body(el : @rdom.Element) -> Unit =
  #| (el) => document.body.appendChild(el)
