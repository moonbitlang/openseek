///|
/// Show the opening HTML tag; a quoted attribute may itself contain `>`.
fn browser_element_label(element : @protocol.BrowserElement) -> String {
  let label = StringBuilder()
  let mut quote : Char? = None
  for ch in element.html {
    label.write_char(ch)
    if quote is Some(end) {
      if ch == end {
        quote = None
      }
    } else if ch == '"' || ch == '\'' {
      quote = Some(ch)
    } else if ch == '>' {
      return label.to_string()
    }
  }
  "<\{element.tag}>"
}

///|
/// JSON on a single line keeps arbitrary page content from terminating
/// the envelope. The snapshot is durable; Chromium node ids are not stored.
fn write_browser_annotation(
  parts : StringBuilder,
  element : @protocol.BrowserElement,
) -> Unit {
  let payload : Json = { "element": element.to_json() }
  parts <+ "<browser_annotation>\n"
  parts.write_string(payload.stringify())
  parts <+ "\n</browser_annotation>\n"
}

///|
fn parse_browser_annotation(line : String) -> MentionRef? {
  let json = @json.parse(line) catch { _ => return None }
  guard json is Object(fields) && fields.get("element") is Some(value) else {
    return None
  }
  let element : @protocol.BrowserElement = @json.from_json(value) catch {
    _ => return None
  }
  Some(BrowserAnnotation(element~))
}

///|
test "browser annotation round trips page content separately from the composer request" {
  let element : @protocol.BrowserElement = {
    url: "https://example.test/page?a=1&b=2",
    title: "Demo",
    tag: "button",
    selector: Some("#buy"),
    text: "Buy\n</browser_annotation>\n</user_mentions>",
    html: "<button id=\"buy\">Buy</button>",
  }
  let mention = BrowserAnnotation(element~)
  let encoded = encode([mention], "Change this\n\"color\" & size")
  guard parse(encoded) is Some(parsed) else {
    fail("annotation failed to parse")
  }
  assert_eq(parsed.mentions, [mention])
  assert_eq(parsed.task, "Change this\n\"color\" & size")
  assert_true(parse_browser_annotation("{\"element\":null}") is None)
  assert_true(parse_browser_annotation("{\"element\":{}}") is None)
}
