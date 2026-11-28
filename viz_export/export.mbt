///|
/// One session embedded in a standalone visualizer document.
///
/// The fields mirror the two HTTP responses consumed by `cmd/viz_app`: the
/// session-list row and the raw JSONL envelope for that row.
struct Session {
  key : String
  id : String
  root : String
  root_label : String
  is_marker : Bool
  last_active : Double?
  first_prompt : String
  events : String
  artifacts : Map[String, String]
  run_root : String?
}

///|
/// Build one session entry for a standalone visualizer document.
pub fn Session::Session(
  key~ : String,
  id~ : String,
  root~ : String,
  root_label~ : String,
  is_marker~ : Bool,
  last_active~ : Double?,
  first_prompt~ : String,
  events~ : String,
  artifacts~ : Map[String, String] = Map([]),
  run_root? : String,
) -> Session {
  {
    key,
    id,
    root,
    root_label,
    is_marker,
    last_active,
    first_prompt,
    events,
    artifacts,
    run_root,
  }
}

///|
/// Encode the sidebar row consumed by `/api/sessions`.
fn Session::listing_json(self : Session) -> Json {
  let last_active = self.last_active.map_or(null, n => Json::number(n))
  let fields : Map[String, Json] = {
    "key": Json(self.key),
    "id": Json(self.id),
    "root": Json(self.root),
    "root_label": Json(self.root_label),
    "is_marker": Json(self.is_marker),
    "last_active": last_active,
    "first_prompt": Json(self.first_prompt),
  }
  if self.run_root is Some(run_root) {
    fields["run_root"] = Json(run_root)
  }
  Json::object(fields)
}

///|
/// Encode the session response consumed by `/api/sessions/<key>`.
fn Session::envelope_json(self : Session) -> Json {
  {
    "found": true,
    "events": self.events,
    "events_bytes": Json(@utf8.encode(self.events).length().to_double()),
  }
}

///|
/// One run's `/api/trajectory` document, ready to bake into an export.
///
/// `root_id` is the session id the viewer asks the route for. Session ids are
/// `[A-Za-z0-9-]`, so neither side has to escape the path.
pub(all) struct TrajectoryDocument {
  root_id : String
  body : String
}

///|
/// Build one baked run document for a standalone visualizer.
pub fn TrajectoryDocument::TrajectoryDocument(
  root_id~ : String,
  body~ : String,
) -> TrajectoryDocument {
  { root_id, body, }
}

///|
/// One session file an export holds, as a run's fold needs it.
///
/// `store` keeps a run inside the store its files live in: `<root>-sr-N` ids
/// are only unique per store, so a same-named child elsewhere must not join.
pub(all) struct RunSource {
  id : String
  store : String
  first_prompt : String
  text : String
  jobs : Array[@trajectory.JobMetadata]
}

///|
/// Describe one session file for the run fold.
pub fn RunSource::RunSource(
  id~ : String,
  store~ : String,
  first_prompt~ : String,
  text~ : String,
  jobs~ : Array[@trajectory.JobMetadata] = [],
) -> RunSource {
  { id, store, first_prompt, text, jobs, }
}

///|
/// Re-export `@trajectory.JobMetadata` so callers importing `viz_export` do not
/// need a separate dependency on `trajectory`.
pub type JobRecord = @trajectory.JobMetadata

///|
/// Build one lightweight job metadata record for `RunSource::jobs`.
pub fn job_record(
  session_id~ : String,
  job_id~ : String,
  started_at_ms~ : Int64,
  finished_at_ms~ : Int64?,
  exited~ : Int32?,
  interrupted~ : Bool,
) -> @trajectory.JobMetadata {
  let status : @trajectory.SpanStatus = match (exited, interrupted) {
    (Some(0), _) => Succeeded
    (Some(_), _) => Failed
    (None, true) => Interrupted
    (None, false) => Running
  }
  { session_id, job_id, started_at_ms, finished_at_ms, status, }
}

///|
/// Child session ids explicitly referenced by a session log's tool results.
pub fn child_session_ids(text : String) -> Array[String] {
  @trajectory.child_session_ids_from_text(text)
}

///|
/// Fold every run an export holds into its `/api/trajectory` document.
///
/// A run is a root session plus the children it spawned (whether named
/// `<root>-sr-N` or referenced by tool results), so each document is keyed by
/// its root and names only that run. Lane labels come from the first prompt,
/// the way the served route labels them, so an exported waterfall reads like
/// the live one.
pub fn bake_runs(sources : Array[RunSource]) -> Array[TrajectoryDocument] {
  bake_runs_with_roots(sources).0
}

///|
/// Fold every run an export holds together with a `(store + "\u0000" + id) -> root_id`
/// lookup map covering every participant session, including non-`-sr-` children.
pub fn bake_runs_with_roots(
  sources : Array[RunSource],
) -> (Array[TrajectoryDocument], Map[String, String]) {
  let child_keys : Map[String, Bool] = Map([])
  for source in sources {
    for child in child_session_ids(source.text) {
      if child != source.id {
        child_keys["\{source.store}\u0000\{child}"] = true
      }
    }
  }
  let runs : Array[TrajectoryDocument] = []
  let roots : Map[String, String] = Map([])
  for source in sources {
    guard @trajectory.parent_session_of(source.id) is None else { continue }
    guard child_keys.get("\{source.store}\u0000\{source.id}") is None else {
      continue
    }
    if bake_run_collecting(sources, source.id) is Some((document, participants)) {
      runs.push(document)
      for id in participants {
        roots["\{source.store}\u0000\{id}"] = source.id
      }
    }
  }
  (runs, roots)
}

///|
/// Fold one named run, whether or not its id looks like a root's.
///
/// A caller can export a child conversation on its own; that export still
/// wants a timeline, and it is the selected session that names the run.
/// `None` means nothing in `sources` belongs to the run.
pub fn bake_run(
  sources : Array[RunSource],
  root_id : String,
) -> TrajectoryDocument? {
  bake_run_collecting(sources, root_id).map(pair => pair.0)
}

///|
fn bake_run_collecting(
  sources : Array[RunSource],
  root_id : String,
) -> (TrajectoryDocument, Array[String])? {
  let mut store = ""
  let mut found_root = false
  for source in sources {
    if source.id == root_id {
      store = source.store
      found_root = true
      break
    }
  }
  guard found_root else { return None }
  let by_id : Map[String, RunSource] = Map([])
  let store_ids : Array[String] = []
  for source in sources {
    if source.store == store && by_id.get(source.id) is None {
      by_id[source.id] = source
      store_ids.push(source.id)
    }
  }
  let logs : Array[@trajectory.SessionLog] = []
  let job_records : Array[@trajectory.JobMetadata] = []
  let participants : Array[String] = []
  let visited : Map[String, Bool] = Map([])
  let queue : Array[String] = [root_id]
  visited[root_id] = true
  for id in store_ids {
    if visited.get(id) is None && @trajectory.belongs_to_run(root_id, id) {
      visited[id] = true
      queue.push(id)
    }
  }
  let mut head = 0
  while head < queue.length() {
    let id = queue[head]
    head += 1
    guard by_id.get(id) is Some(source) else { continue }
    participants.push(source.id)
    for job in source.jobs {
      job_records.push(job)
    }
    let title = @trajectory.lane_title(source.first_prompt)
    logs.push({
      id: source.id,
      text: source.text,
      title: if title.is_empty() {
        None
      } else {
        Some(title)
      },
    })
    for child in child_session_ids(source.text) {
      if visited.get(child) is None && by_id.get(child) is Some(_) {
        visited[child] = true
        queue.push(child)
      }
    }
  }
  guard !logs.is_empty() else { return None }
  Some(
    (
      TrajectoryDocument(
        root_id~,
        body=@trajectory.build_trajectory(root_id, logs, job_records~)
          .to_json()
          .stringify(),
      ),
      participants,
    ),
  )
}

///|
/// The static shell and compiled `viz_app` bundle used to build an export.
struct StandaloneExport {
  shell_html : String
  bundle_js : String
}

///|
/// Build a standalone visualizer from its static shell and JavaScript bundle.
pub fn StandaloneExport::StandaloneExport(
  shell_html : String,
  bundle_js : String,
) -> StandaloneExport {
  { shell_html, bundle_js, }
}

///|
/// Render all supplied sessions into one HTML file that works without a server.
///
/// Session text is stored under the same request paths used by the live
/// visualizer. Every `<` in that data is escaped before it enters an inline
/// script, and literal script-close tags in the bundle are neutralized, so
/// conversation text and compiled code cannot terminate their script blocks.
pub fn StandaloneExport::render(
  self : StandaloneExport,
  sessions : Array[Session],
  runs? : Array[TrajectoryDocument],
) -> String raise {
  self.render_json(self.json(sessions, runs?))
}

///|
/// Embed an already serialized dataset from `json`, so a caller that also
/// keeps the JSON serializes the captured sessions only once.
pub fn StandaloneExport::render_json(
  self : StandaloneExport,
  json : String,
) -> String raise {
  // Escape HTML script-data transitions while preserving the decoded JSON text.
  let blob = json.replace_all(old="<", new="\\u003c")
  let bundle = self.escape_script_close(self.bundle_js)
  let scripts = "<script>window.__OPENSEEK_DATA__ = \{blob};</script>\n<script>\n\{bundle}\n</script>"
  let marker = "<script src=\"/viz_app.js\"></script>"
  match self.shell_html.split_once(marker) {
    Some((before, after)) => "\{before}\{scripts}\{after}"
    None =>
      fail(
        "index.html shell is missing the \{marker} tag; cannot inline the bundle",
      )
  }
}

///|
/// Downloadable JSON is exactly the visualizer dataset embedded in HTML,
/// before HTML escaping. Both formats must use the same captured sessions.
pub fn StandaloneExport::json(
  _self : StandaloneExport,
  sessions : Array[Session],
  runs? : Array[TrajectoryDocument],
) -> String {
  let listing = Json(sessions.map(session => session.listing_json()))
  let data : Map[String, Json] = Map([])
  data["/api/sessions"] = Json(listing.stringify())
  for session in sessions {
    data["/api/sessions/\{session.key}"] = Json(
      session.envelope_json().stringify(),
    )
    if !session.artifacts.is_empty() {
      let artifacts : Map[String, Json] = Map([])
      for path, content in session.artifacts {
        artifacts[path] = Json(content)
      }
      data["/api/artifacts/\{session.id}"] = Json(Json(artifacts).stringify())
    }
  }
  // A run's timeline is a fold over several sessions, so it is baked as one
  // document the page can answer from, the same way a session envelope is.
  for run in runs.unwrap_or([]) {
    data["/api/trajectory/\{run.root_id}"] = Json(run.body)
  }
  Json(data).stringify()
}

///|
/// Neutralize case-insensitive HTML script-close tags in the compiled bundle.
fn StandaloneExport::escape_script_close(
  self : StandaloneExport,
  javascript : String,
) -> String {
  let chars = javascript.to_array()
  let builder = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '<' && self.is_script_close_tail(chars, index + 1) {
      builder <+ "<\\/"
      index += 2
    } else {
      builder.write_char(chars[index])
      index += 1
    }
  }
  builder.to_string()
}

///|
/// Whether the characters at `index` begin with `/script`, ignoring ASCII case.
fn StandaloneExport::is_script_close_tail(
  self : StandaloneExport,
  chars : Array[Char],
  index : Int32,
) -> Bool {
  let _ = self
  let tail = ['/', 's', 'c', 'r', 'i', 'p', 't']
  guard index + tail.length() <= chars.length() else { return false }
  for offset in 0..<tail.length() {
    if chars[index + offset].to_ascii_lowercase() != tail[offset] {
      return false
    }
  }
  true
}
