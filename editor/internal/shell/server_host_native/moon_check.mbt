///|
/// Push source for workspace diagnostics: runs `moon check --output-json` and
/// publishes the parsed per-file diagnostics through `publish`. Runs are
/// single-flight — document syncs arriving while a check is in flight
/// collapse into one follow-up run.
pub struct MoonCheckDiagnostics {
  priv root : String
  priv moon_command : String
  priv publish : (@base_common.Uri, String, Array[@language.Diagnostic]) -> Unit
  priv running : Ref[Bool]
  priv dirty : Ref[Bool]
  /// Latest synced revision per workspace URI, stamped onto pushed packets.
  priv revisions : Map[String, String]
  /// Last pushed set per workspace URI, replayed on document sync and used to
  /// push clears for files whose diagnostics disappeared.
  priv published : Ref[Map[String, Array[@language.Diagnostic]]]
}

///|
/// Creates a diagnostics runner for the workspace rooted at `root`.
pub fn MoonCheckDiagnostics::MoonCheckDiagnostics(
  root : String,
  publish : (@base_common.Uri, String, Array[@language.Diagnostic]) -> Unit,
  moon_command? : String = "moon",
) -> MoonCheckDiagnostics {
  {
    root: normalize_host_path(root),
    moon_command,
    publish,
    running: Ref(false),
    dirty: Ref(false),
    revisions: Default::default(),
    published: Ref(Default::default()),
  }
}

///|
/// Records the latest synced revision and replays the last published set so a
/// freshly opened document paints known markers before the next check lands.
pub fn MoonCheckDiagnostics::note_document(
  self : MoonCheckDiagnostics,
  document : @workspace.DocumentSnapshot,
) -> Unit {
  let key = document.uri.to_string()
  self.revisions.set(key, document.revision)
  match self.published.val.get(key) {
    Some(diagnostics) => self.emit(key, diagnostics)
    None => ()
  }
}

///|
/// Schedules a `moon check` run on `spawn_task`; a run already in flight
/// absorbs this request and re-runs once after it finishes.
pub fn MoonCheckDiagnostics::schedule(
  self : MoonCheckDiagnostics,
  spawn_task : (async () -> Unit) -> Unit,
) -> Unit {
  if self.running.val {
    self.dirty.val = true
    return
  }
  self.running.val = true
  spawn_task(() => {
    for ;; {
      self.dirty.val = false
      self.run_once()
      if !self.dirty.val {
        break
      }
    }
    self.running.val = false
  })
}

///|
async fn MoonCheckDiagnostics::run_once(self : MoonCheckDiagnostics) -> Unit {
  // `moon check` exits nonzero whenever errors exist, so the exit code is
  // ignored and stdout is parsed unconditionally; only a spawn/read failure
  // skips publishing.
  let raw = Some(
    @process.collect_stdout(
      self.moon_command,
      ["check", "--output-json"],
      cwd=self.root,
    ).1.text(),
  ) catch {
    _ => None
  }
  guard raw is Some(raw) else { return }
  let next = parse_moon_check_diagnostics(self.root, raw)
  for key, _diagnostics in self.published.val {
    if !next.contains(key) {
      self.emit(key, [])
    }
  }
  for key, diagnostics in next {
    self.emit(key, diagnostics)
  }
  self.published.val = next
}

///|
fn MoonCheckDiagnostics::emit(
  self : MoonCheckDiagnostics,
  uri_key : String,
  diagnostics : Array[@language.Diagnostic],
) -> Unit {
  let uri = Some(@base_common.Uri::parse(uri_key)) catch { _ => None }
  match uri {
    Some(uri) =>
      (self.publish)(
        uri,
        self.revisions.get(uri_key).unwrap_or(""),
        diagnostics,
      )
    None => ()
  }
}

///|
/// Parses `moon check --output-json` output — one JSON diagnostic per line —
/// into diagnostics grouped by remote workspace URI. Diagnostic paths outside
/// `root` and non-diagnostic lines are dropped. `loc` is 1-based
/// `line:col-line:col` with an exclusive end column, matching the viewer's
/// range convention directly.
pub fn parse_moon_check_diagnostics(
  root : String,
  raw : String,
) -> Map[String, Array[@language.Diagnostic]] {
  let prefix = normalize_host_path(root) + "/"
  let grouped : Map[String, Array[@language.Diagnostic]] = Default::default()
  for line in raw.split("\n") {
    let trimmed = line.trim(char_set="\r\n ").to_owned()
    if trimmed == "" {
      continue
    }
    match (Some(@json.parse(trimmed)) catch { _ => None }) {
      Some(
        {
          "$message_type": "diagnostic",
          "level": String(level),
          "path": String(path),
          "loc": String(loc),
          "message": String(message),
          ..
        }
      ) => {
        let normalized = normalize_host_path(path)
        if !normalized.has_prefix(prefix) {
          continue
        }
        let relative = normalized[prefix.length():].to_owned()
        match (parse_moon_loc(loc), @server.remote_document_uri(relative)) {
          (Some(range), Some(uri)) => {
            let diagnostic : @language.Diagnostic = {
              range,
              severity: check_level_severity(level),
              message,
              tags: None,
            }
            match grouped.get(uri.to_string()) {
              Some(diagnostics) => diagnostics.push(diagnostic)
              None => grouped.set(uri.to_string(), [diagnostic])
            }
          }
          _ => ()
        }
      }
      _ => ()
    }
  }
  grouped
}

///|
fn check_level_severity(level : String) -> @language.DiagnosticSeverity {
  match level {
    "error" => Error
    "warning" => Warning
    _ => Info
  }
}

///|
/// Parses a `moon check` location: `line:col-line:col`, or a bare `line:col`
/// which degrades to an empty range at that position.
fn parse_moon_loc(loc : String) -> @base_common.Range? {
  match loc.find("-") {
    Some(dash) =>
      match
        (
          parse_check_position(loc[0:dash]),
          parse_check_position(loc[dash + 1:]),
        ) {
        (Some(start), Some(end)) =>
          Some(@base_common.Range::from_positions(start, end))
        _ => None
      }
    None =>
      match parse_check_position(loc[:]) {
        Some(position) =>
          Some(@base_common.Range::from_positions(position, position))
        None => None
      }
  }
}

///|
fn parse_check_position(view : StringView) -> @base_common.Position? {
  match view.find(":") {
    Some(colon) => {
      let parsed = Some(
        (
          @string.parse_int(view[0:colon], base=10),
          @string.parse_int(view[colon + 1:], base=10),
        ),
      ) catch {
        _ => None
      }
      match parsed {
        Some((line, column)) => Some(Position(line, column))
        None => None
      }
    }
    None => None
  }
}
