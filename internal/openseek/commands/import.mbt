///|
/// Largest export `sessions import` reads, matching the desktop's file and
/// share-download limits.
const ImportMaxBytes : Int32 = 16 * 1024 * 1024

///|
/// Listing roots of a Cloud export start with this; a local export names the
/// absolute session store it was read from.
const CloudRootPrefix = "cloud://"

///|
/// Where an exported conversation was recorded. An import only recreates a
/// conversation in the kind of place it came from.
priv enum ImportOrigin {
  Local
  Cloud
}

///|
/// One session of an export, already validated and stripped of its id: the
/// parent has an empty suffix and each direct subrun keeps its `-sr-<n>`.
priv struct ImportedSession {
  suffix : String
  title : String
  log : @log.ParsedLog
  system_prompt : String
}

///|
fn parse_json(text : StringView) -> Json? {
  Some(@json.parse(text)) catch {
    _ => None
  }
}

///|
fn import_origin(matches : @argparse.Matches) -> ImportOrigin raise {
  match matches {
    { values: { "origin": ["local", ..], .. }, .. } => Local
    { values: { "origin": ["cloud", ..], .. }, .. } => Cloud
    { values: { "origin": [other, ..], .. }, .. } =>
      fail("--origin must be local or cloud, got: \{other}")
    _ => fail("`openseek sessions import` requires --origin")
  }
}

///|
/// The `-sr-<n>` suffix of a direct subrun of `parent`. Exports carry only a
/// conversation and its direct subruns.
fn direct_subrun_suffix(parent : String, id : String) -> String? {
  guard id.strip_prefix(parent + "-sr-") is Some(ordinal) &&
    ordinal.length() is (1..<=9) &&
    ordinal.iter().all(c => c.is_ascii_digit()) else {
    return None
  }
  Some("-sr-\{ordinal}")
}

///|
/// Validate a conversation export (the visualizer dataset `viz_export`
/// writes) and return its sessions, parent first. Every record must be a
/// complete, undamaged log whose events are numbered from one without gaps,
/// and every listed root must belong to `origin`.
fn decode_export(
  text : String,
  origin : ImportOrigin,
) -> Array[ImportedSession] raise {
  guard parse_json(text) is Some(Object(dataset)) &&
    dataset.get("/api/sessions") is Some(String(listing)) &&
    parse_json(listing) is Some(Array(rows)) &&
    !rows.is_empty() else {
    fail("Expected an OpenSeek conversation export JSON file.")
  }
  let sessions : Array[ImportedSession] = []
  let keys : Map[String, Unit] = Map([])
  let suffixes : Map[String, Unit] = Map([])
  let mut parent : String? = None
  for row in rows {
    guard row
      is {
        "key": String(key),
        "id": String(id),
        "root": String(root),
        "first_prompt": String(title),
        ..
      } &&
      !key.is_empty() &&
      !keys.contains(key) &&
      dataset.get("/api/sessions/\{key}") is Some(String(envelope)) &&
      parse_json(envelope)
      is Some({ "found": True, "events": String(events), .. }) else {
      fail("The export contains a missing or invalid session record.")
    }
    keys[key] = ()
    match (origin, root.has_prefix(CloudRootPrefix)) {
      (Local, true) =>
        fail(
          "This conversation was exported from Cloud. Import it into Cloud chats.",
        )
      (Cloud, false) =>
        fail(
          "This conversation was exported from a local workspace. Import it into a local workspace.",
        )
      _ => ()
    }
    let parsed = @log.parse_events(events)
    guard parsed.header is Some(header) &&
      header.id == id &&
      parsed.errors.is_empty() &&
      !parsed.partial_tail else {
      fail(
        "The export contains an unsupported, damaged or incomplete session log.",
      )
    }
    for index, event in parsed.events {
      guard event.sequence() == index + 1 else {
        fail("Session event sequences must be contiguous.")
      }
    }
    let suffix = match parent {
      None => {
        parent = Some(id)
        ""
      }
      Some(parent) =>
        match direct_subrun_suffix(parent, id) {
          Some(suffix) => suffix
          None => fail("Expected one conversation and its subruns.")
        }
    }
    guard !suffixes.contains(suffix) else {
      fail("Expected one conversation and its subruns.")
    }
    suffixes[suffix] = ()
    sessions.push({
      suffix,
      title,
      log: parsed,
      system_prompt: header.system_prompt,
    })
  }
  sessions
}

///|
/// `openseek sessions import --source <file> --origin <local|cloud> [--as <id>]`:
/// recreate an exported conversation, with its direct subruns, as a new
/// session in this store. The conversation's system prompt is the one a new
/// session started with this command's `--dir`, `--model`, and prompt options
/// would get, with the new session's own scratch directory: an exported
/// prompt names the workspace and scratch of the session it came from.
/// Subruns keep their own prompts, which name no location. Prints
/// `{"session_id", "title"}`, `title` being `null` when the export has none.
async fn sessions_import(matches : @argparse.Matches) -> Unit {
  let workspace_root = @setup.prepare_workspace_root(matches, log_created=false)
  let store = @store.SessionStore(@setup.session_root(matches, workspace_root~))
  let id = match matches {
    { values: { "as": [id, ..], .. }, .. } => {
      guard !id.is_blank() else { fail("--as needs a session id") }
      @agent_session.SessionId(id.trim().to_owned())
    }
    _ => @setup.generated_session_id()
  }
  let source = match matches {
    { values: { "source": [path, ..], .. }, .. } if !path.is_blank() =>
      @workspace_path.resolve(workspace_root, path.trim().to_owned())
    _ => fail("`openseek sessions import` requires --source")
  }
  let origin = import_origin(matches)
  let bytes = @fs.read_file(source).binary()
  guard bytes.length() <= ImportMaxBytes else {
    fail("JSON must be no larger than 16 MiB.")
  }
  let text = @utf8.decode(bytes) catch {
    _ => fail("Expected an OpenSeek conversation export JSON file.")
  }
  let sessions = decode_export(text, origin)
  let ids = sessions.map(session => {
    @agent_session.SessionId(id.value() + session.suffix)
  })
  for target in ids {
    guard !store.exists(target) else {
      fail("session \{target.value()} already exists")
    }
  }
  let (model, _, _) = @options.agent_settings(matches)
  let system_prompt = @setup.configured_system_prompt(
    matches,
    model,
    workspace_root~,
    session_scratch_dir=store.scratch_dir(id),
  )
  // Subruns first and the conversation last, so a store never lists a
  // conversation whose subruns are missing; a failed import removes what it
  // wrote.
  errdefer @async.protect_from_cancel(() => {
    for target in ids {
      guard @workspace_path.parent_dir(store.session_file(target)) is Some(dir) else {
        continue
      }
      @fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
    }
  })
  for index = sessions.length() - 1; index >= 0; index = index - 1 {
    let session = sessions[index]
    store.create(
      @log.session_from_parse(
        session.log,
        id=ids[index].value(),
        system_prompt=if index == 0 {
          system_prompt
        } else {
          session.system_prompt
        },
      ),
    )
  }
  let title = sessions[0].title.trim()
  let title : Json = if title.is_empty() {
    null
  } else {
    store.set_title(id, title.to_owned())
    Json(title.to_owned())
  }
  let reply : Json = { "session_id": id.value(), "title": title }
  println(reply.stringify())
}
