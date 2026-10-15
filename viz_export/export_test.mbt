///|
test "@viz_export renders standalone data and neutralizes script endings" {
  let session = @viz_export.Session(
    key="session-key",
    id="session-id",
    root="/workspace/.openseek",
    root_label="workspace",
    is_marker=true,
    last_active=Some(42.0),
    first_prompt="show <script>alert(1)</script>",
    events="{\"message\":\"<!-- <script>unsafe</script>\"}\n",
  )
  let exporter = @viz_export.StandaloneExport(
    "<html><body><script src=\"/viz_app.js\"></script></body></html>", "globalThis.ready = true; /* </SCRIPT> */",
  )
  let html = exporter.render([session])
  // JSON downloads carry exactly the same records as the HTML's embedded
  // dataset, without applying HTML script escaping to the downloaded file.
  let json = exporter.json([session])
  assert_true(json.contains("unsafe</script>"))
  assert_eq(exporter.render_json(json), html)
  let escaped = json.replace_all(old="<", new="\\u003c")
  assert_true(html.contains("window.__OPENSEEK_DATA__ = \{escaped};"))
  assert_true(html.contains("<\\/SCRIPT>"))
  assert_false(html.contains("<script src=\"/viz_app.js\"></script>"))
  assert_false(html.contains("unsafe</script>"))
}

///|
test "@viz_export requires the visualizer bundle marker" {
  let mut rejected = false
  ignore(
    @viz_export.StandaloneExport("<html></html>", "bundle").render([]) catch {
      _ => {
        rejected = true
        ""
      }
    },
  )
  assert_true(rejected)
}

///|
test "streamed exports match existing serialization across escaping and Unicode boundaries" {
  let events = "a".repeat(4095) +
    "😀\"\\\n\r\t\u0000</script><!--" +
    "中é😀<\\\"\n".repeat(9000)
  let session = @viz_export.Session(
    key="session-key",
    id="id",
    root="/workspace",
    root_label="工作区",
    is_marker=true,
    last_active=None,
    first_prompt="<\"😀",
    events~,
  )
  let exporter = @viz_export.StandaloneExport(
    "<html><script src=\"/viz_app.js\"></script></html>",
    "x".repeat(4095) + "</ScRiPt>" + "😀".repeat(4095) + "</script><",
  )
  let sessions = [session]
  let json = exporter.json(sessions)
  let html = exporter.render(sessions)
  assert_eq(exporter.json_chunks(sessions).join(""), json)
  let streamed = exporter.html_chunks(sessions).join("")
  assert_true(streamed == html)
  // Reopening streams must replay the same bytes, independently of consumption.
  let first = exporter.html_chunks(sessions)
  ignore(first.next())
  assert_true(exporter.html_chunks(sessions).join("") == html)
  for
    chunk in exporter
    .json_chunks(sessions)
    .concat(exporter.html_chunks(sessions)) {
    assert_true(chunk.length() < 64 * 1024)
  }
  assert_eq(exporter.json_chunks([]).join(""), exporter.json([]))
}
