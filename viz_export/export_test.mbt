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
    artifacts=Map::from_array([
      (
        "scratch/artifact/chart.html", "<button>plot</button><script>plot()</script>",
      ),
    ]),
  )
  let exporter = @viz_export.StandaloneExport(
    "<html><body><script src=\"/viz_app.js\"></script></body></html>", "globalThis.ready = true; /* </SCRIPT> */",
  )
  let html = exporter.render([session])
  // JSON downloads carry exactly the same records as the HTML's embedded
  // dataset, without applying HTML script escaping to the downloaded file.
  let json = exporter.json([session])
  assert_true(json.contains("unsafe</script>"))
  assert_true(json.contains("/api/artifacts/session-id"))
  assert_true(json.contains("scratch/artifact/chart.html"))
  assert_true(json.contains("<button>plot</button>"))
  assert_eq(exporter.render_json(json), html)
  let escaped = json.replace_all(old="<", new="\\u003c")
  assert_true(html.contains("window.__OPENSEEK_DATA__ = \{escaped};"))
  assert_true(html.contains("<\\/SCRIPT>"))
  assert_false(html.contains("<script src=\"/viz_app.js\"></script>"))
  assert_false(html.contains("unsafe</script>"))
  assert_false(html.contains("<button>plot</button>"))
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
test "@viz_export bakes a run's trajectory beside the sessions it folds" {
  let session = @viz_export.Session(
    key="run",
    id="run",
    root="/workspace/.openseek",
    root_label="workspace",
    is_marker=true,
    last_active=Some(42.0),
    first_prompt="delegate",
    events="{\"version\":1,\"id\":\"run\"}\n",
  )
  let exporter = @viz_export.StandaloneExport(
    "<html><body><script src=\"/viz_app.js\"></script></body></html>", "globalThis.ready = true;",
  )
  let run = @viz_export.TrajectoryDocument(
    root_id="run",
    body="{\"root_session_id\":\"run\",\"spans\":[]}",
  )
  let json = exporter.json([session], runs=[run])
  // Keyed by the path the viewer asks for, so the page answers without a server.
  assert_true(json.contains("/api/trajectory/run"))
  assert_true(json.contains("root_session_id"))
  // Without runs the archive is exactly what it was before.
  assert_false(exporter.json([session]).contains("/api/trajectory"))
}

///|
/// A minimal durable session log: one header line and one user event, which is
/// all the run fold needs to give a session a lane and a turn.
fn probe_log(id : String, prompt : String) -> String {
  "{\"version\":1,\"id\":\"\{id}\",\"system_prompt\":\"\"}\n" +
  "{\"sequence\":1,\"ts\":1000,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"\{prompt}\"}}}\n"
}

///|
test "@viz_export folds one document per run, inside its own store" {
  let sources = [
    @viz_export.RunSource(
      id="run",
      store="/a",
      first_prompt="delegate",
      text=probe_log("run", "delegate"),
    ),
    RunSource(
      id="run-sr-1",
      store="/a",
      first_prompt="scout the parser",
      text=probe_log("run-sr-1", "scout the parser"),
    ),
    // The same run id in another store: `<root>-sr-N` ids are only unique per
    // store, so this child must never join the first store's timeline.
    RunSource(
      id="run-sr-1",
      store="/b",
      first_prompt="theirs",
      text=probe_log("run-sr-1", "theirs"),
    ),
  ]
  let runs = @viz_export.bake_runs(sources)
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].root_id, "run")
  assert_true(runs[0].body.contains("scout the parser"))
  assert_false(runs[0].body.contains("theirs"))
  // Naming the run explicitly folds a child's own export too, which is what a
  // reader who exported one subagent conversation asked for.
  guard @viz_export.bake_run(sources, "run-sr-1") is Some(child) else {
    fail("naming a run must fold its document")
  }
  assert_eq(child.root_id, "run-sr-1")
  assert_true(child.body.contains("scout the parser"))
  assert_false(child.body.contains("theirs"))
  // A run nothing belongs to bakes nothing rather than an empty timeline.
  assert_true(@viz_export.bake_run(sources, "absent") is None)
}

///|
test "@viz_export groups non-sr child sessions under their parent run" {
  let parent_log = probe_log("run", "delegate") +
    "{\"sequence\":2,\"ts\":1100,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"\",\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"subagent\",\"arguments\":\"{}\"}}],\"started_at_ms\":1050}}}\n" +
    "{\"sequence\":3,\"ts\":1500,\"item\":{\"kind\":\"tool_result\",\"payload\":{\"tool_call_id\":\"c1\",\"tool_name\":\"subagent\",\"content\":\"ok\",\"is_error\":false,\"data\":{\"session\":\"custom-child\"}}}}\n"
  let sources = [
    @viz_export.RunSource(
      id="run",
      store="/a",
      first_prompt="delegate",
      text=parent_log,
    ),
    RunSource(
      id="custom-child",
      store="/a",
      first_prompt="custom worker",
      text=probe_log("custom-child", "custom worker"),
    ),
  ]
  let runs = @viz_export.bake_runs(sources)
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].root_id, "run")
  assert_true(runs[0].body.contains("custom worker"))
  let (_, roots) = @viz_export.bake_runs_with_roots(sources)
  assert_eq(roots.get("/a\u0000run"), Some("run"))
  assert_eq(roots.get("/a\u0000custom-child"), Some("run"))
}

///|
test "@viz_export passes lightweight job_records into the trajectory fold" {
  let text = probe_log("run", "job") +
    "{\"sequence\":2,\"ts\":1100,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"\",\"tool_calls\":[{\"id\":\"j1\",\"name\":\"shell_exec\",\"arguments\":\"{}\"}],\"started_at_ms\":\"1050\"}}}\n" +
    "{\"sequence\":3,\"ts\":1200,\"item\":{\"kind\":\"tool_result\",\"payload\":{\"tool_call_id\":\"j1\",\"tool_name\":\"shell_exec\",\"content\":\"started in background as job bg-1\",\"is_error\":false}}}\n"
  let doc = @viz_export.bake_run(
    [
      RunSource(id="run", store="/a", first_prompt="job", text~, jobs=[
        @viz_export.job_record(
          session_id="run",
          job_id="bg-1",
          started_at_ms=1060L,
          finished_at_ms=Some(1860L),
          exited=Some(0),
          interrupted=false,
        ),
      ]),
    ],
    "run",
  )
  guard doc is Some(doc) else { fail("expected baked trajectory") }
  assert_true(doc.body.contains("\"ended_at_ms\":1860"))
}
