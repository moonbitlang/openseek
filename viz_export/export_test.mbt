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
