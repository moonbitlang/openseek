///|
/// Push source for workspace diagnostics: runs `moon check --output-json` and
/// publishes the parsed per-file diagnostics through `publish`. Runs are
/// single-flight — document syncs arriving while a check is in flight
/// collapse into one follow-up run.
struct MoonCheckDiagnostics {
  /// Shared with the host's workspace switching; each run captures one value.
  root : Ref[String]
  publish : (@base_common.Uri, String, Array[@language.Diagnostic]) -> Unit
  collect_check : async () -> String?
  running : Ref[Bool]
  dirty : Ref[Bool]
  sync_generation : Ref[Int]
  /// Exact synced model state per workspace URI.
  documents : Map[String, SyncedDocumentStamp]
  /// Last accepted set per workspace URI, including its producing state.
  published : Ref[Map[String, PublishedDiagnosticSet]]
}

///|
priv struct SyncedDocumentStamp {
  revision : String
  normalized_text : String
}

///|
priv struct PublishedDiagnosticSet {
  revision : String
  normalized_text : String
  diagnostics : Array[@language.Diagnostic]
}

///|
/// Creates a diagnostics runner over a shared workspace root.
fn new_native_moon_check_diagnostics(
  root : Ref[String],
  publish : (@base_common.Uri, String, Array[@language.Diagnostic]) -> Unit,
  moon_command? : String = "moon",
) -> MoonCheckDiagnostics {
  new_moon_check_diagnostics(root, publish, () => {
    // `moon check` exits nonzero whenever errors exist, so the exit code is
    // ignored and stdout is parsed unconditionally.
    Some(
      @process.collect_stdout(
        moon_command,
        ["check", "--output-json"],
        cwd=normalize_host_path(root.val),
      ).1.text(),
    ) catch {
      _ => None
    }
  })
}

///|
fn new_moon_check_diagnostics(
  root : Ref[String],
  publish : (@base_common.Uri, String, Array[@language.Diagnostic]) -> Unit,
  collect_check : async () -> String?,
) -> MoonCheckDiagnostics {
  {
    root,
    publish,
    collect_check,
    running: Ref(false),
    dirty: Ref(false),
    sync_generation: Ref(0),
    documents: {},
    published: Ref({}),
  }
}

///|
/// Forgets every synced document and published diagnostic set. The host calls
/// this when the served workspace root changes: the generation bump makes any
/// in-flight `moon check` run discard its results, and no stale-root
/// diagnostics can replay onto same-named files of the new workspace.
fn MoonCheckDiagnostics::reset_impl(self : MoonCheckDiagnostics) -> Unit {
  self.sync_generation.val += 1
  self.documents.clear()
  self.published.val = {}
}

///|
/// Records the exact synced state. A freshly opened document replays only a
/// diagnostic set produced for the same revision and normalized text.
fn MoonCheckDiagnostics::note_document_impl(
  self : MoonCheckDiagnostics,
  document : @workspace.DocumentSnapshot,
) -> Unit {
  let key = document.uri.to_string()
  let stamp : SyncedDocumentStamp = {
    revision: document.revision,
    normalized_text: @model.TextSnapshot(document.text).get_value(),
  }
  self.sync_generation.val += 1
  self.documents.set(key, stamp)
  if self.running.val {
    self.dirty.val = true
  }
  if self.published.val.get(key) is Some(published) &&
    published.revision == stamp.revision &&
    published.normalized_text == stamp.normalized_text {
    self.emit(key, published.revision, published.diagnostics)
  }
}

///|
/// Schedules a `moon check` run on `spawn_task`; a run already in flight
/// absorbs this request and re-runs once after it finishes.
fn MoonCheckDiagnostics::schedule_impl(
  self : MoonCheckDiagnostics,
  spawn_task : (async () -> Unit) -> Unit,
) -> Unit {
  if self.running.val {
    self.dirty.val = true
    return
  }
  self.running.val = true
  spawn_task(() => {
    // The scheduler may be cancelled or the injected/process collector may
    // raise. A later sync must still be able to start a new run.
    defer {
      self.running.val = false
    }
    for ;; {
      self.dirty.val = false
      self.run_once()
      if !self.dirty.val {
        break
      }
    }
  })
}

///|
async fn MoonCheckDiagnostics::run_once(self : MoonCheckDiagnostics) -> Unit {
  // One root per run; a workspace switch bumps the generation, so a run that
  // raced the switch discards its results below.
  let root = normalize_host_path(self.root.val)
  let generation = self.sync_generation.val
  let documents = copy_synced_documents(self.documents)
  let before = capture_native_disk_snapshots(root, documents)
  let raw = (self.collect_check)()
  let after = capture_native_disk_snapshots(root, documents)
  if self.sync_generation.val != generation ||
    !same_native_disk_snapshot_map(before, after) {
    self.dirty.val = true
    return
  }
  guard raw is Some(raw) else { return }
  let next = parse_moon_check_diagnostics(root, raw)
  let accepted = copy_published_diagnostic_sets(self.published.val)
  for key, document in documents {
    // A stable disk/model mismatch is not a clear for the last accepted model.
    // Preserve that key and continue so historical entries cannot suppress
    // diagnostics for compatible active documents.
    if !native_disk_matches_document(before, key, document) {
      continue
    }
    let diagnostics = next.get(key).unwrap_or([])
    if !diagnostics.is_empty() || self.published.val.contains(key) {
      self.emit(key, document.revision, diagnostics)
    }
    if !diagnostics.is_empty() {
      accepted.set(key, {
        revision: document.revision,
        normalized_text: document.normalized_text,
        diagnostics,
      })
    } else {
      accepted.remove(key)
    }
  }
  self.published.val = accepted
}

///|
fn MoonCheckDiagnostics::emit(
  self : MoonCheckDiagnostics,
  uri_key : String,
  revision : String,
  diagnostics : Array[@language.Diagnostic],
) -> Unit {
  let uri = Some(@base_common.Uri::parse(uri_key)) catch { _ => None }
  if uri is Some(uri) {
    (self.publish)(uri, revision, diagnostics)
  }
}

///|
fn copy_synced_documents(
  documents : Map[String, SyncedDocumentStamp],
) -> Map[String, SyncedDocumentStamp] {
  let copy : Map[String, SyncedDocumentStamp] = Map([])
  for key, document in documents {
    copy.set(key, document)
  }
  copy
}

///|
fn copy_published_diagnostic_sets(
  published : Map[String, PublishedDiagnosticSet],
) -> Map[String, PublishedDiagnosticSet] {
  let copy : Map[String, PublishedDiagnosticSet] = Map([])
  for key, diagnostic_set in published {
    copy.set(key, diagnostic_set)
  }
  copy
}

///|
async fn capture_native_disk_snapshots(
  root : String,
  documents : Map[String, SyncedDocumentStamp],
) -> Map[String, NativeDiskSnapshot] {
  let snapshots : Map[String, NativeDiskSnapshot] = Map([])
  for key, _document in documents {
    let uri = Some(@base_common.Uri::parse(key)) catch { _ => None }
    if uri is Some(uri) {
      match @server.resolve_remote_document_uri(uri) {
        ParsedRemotePath(path) =>
          if read_native_disk_snapshot(root, path) is Some(snapshot) {
            snapshots.set(key, snapshot)
          }
        RemotePathError(_) => ()
      }
    }
  }
  snapshots
}

///|
fn same_native_disk_snapshot_map(
  left : Map[String, NativeDiskSnapshot],
  right : Map[String, NativeDiskSnapshot],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for key, snapshot in left {
    guard right.get(key) is Some(other) && other == snapshot else {
      return false
    }
  }
  true
}

///|
fn native_disk_matches_document(
  snapshots : Map[String, NativeDiskSnapshot],
  key : String,
  document : SyncedDocumentStamp,
) -> Bool {
  snapshots.get(key) is Some(disk) &&
  disk.signature == document.revision &&
  disk.normalized_text == document.normalized_text
}

///|
/// Parses `moon check --output-json` output — one JSON diagnostic per line —
/// into diagnostics grouped by remote workspace URI. Diagnostic paths outside
/// `root` and non-diagnostic lines are dropped. `loc` is 1-based
/// `line:col-line:col` with an exclusive end column, matching the viewer's
/// range convention directly.
fn parse_moon_check_diagnostics_impl(
  root : String,
  raw : String,
) -> Map[String, Array[@language.Diagnostic]] {
  let prefix = "\{normalize_host_path(root)}/"
  let grouped : Map[String, Array[@language.Diagnostic]] = Map([])
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
        let relative = match normalized.strip_prefix(prefix) {
          Some(rest) => rest.to_owned()
          None => continue
        }
        match (parse_moon_loc(loc), @server.remote_document_uri(relative)) {
          (Some(range), Some(uri)) => {
            let diagnostic : @language.Diagnostic = {
              range,
              severity: check_level_severity(level),
              message,
              tags: None,
            }
            grouped.get_or_init(uri.to_string(), () => []).push(diagnostic)
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
  match loc.split_once("-") {
    Some((start_text, end_text)) =>
      match (parse_check_position(start_text), parse_check_position(end_text)) {
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
  match view.split_once(":") {
    Some((line_text, column_text)) => {
      let parsed = Some(
        (
          @string.parse_int(line_text, base=10),
          @string.parse_int(column_text, base=10),
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
