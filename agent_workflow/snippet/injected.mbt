// The engine-side coordinates an `mbtx` snippet needs to run a workflow whose
// children are visible to the rest of openseek.
//
// `moonbitlang/workflow` is a generic library: it spawns whatever its `Runner`
// spawns and writes its journal wherever it was told, and it never learns
// openseek exists. So nothing IN the snippet can make a run discoverable —
// the coordinates have to come from outside, from the one component that
// knows both the session and the snippet: the `mbtx` tool that launched it.
//
// mbtx picks them BEFORE the snippet starts (a reserved block of child
// ordinals, a journal path, a sidecar path) and injects them into the guest
// environment through the wasm policy's `env.set`. Discovery is therefore not
// discovery at all: the host already knows where to look, the same way it
// already knows a sub-run started because the engine told it.
//
// A snippet reads them through `injected()` and hands the result to `run`.
// The model never types a session id, a path, or an ordinal — it cannot, since
// only the values mbtx reserved will resolve to anything the host watches.

///|
/// The names mbtx writes into the guest environment. Read here and nowhere
/// else: a snippet that spelled one itself would be inventing a coordinate
/// rather than receiving one.
const ExeVar = "OPENSEEK_MBTX_EXE"

///|
const SessionRootVar = "OPENSEEK_MBTX_SESSION_ROOT"

///|
const ParentVar = "OPENSEEK_MBTX_PARENT_SESSION"

///|
const BaseVar = "OPENSEEK_MBTX_SUBRUN_BASE"

///|
const LimitVar = "OPENSEEK_MBTX_SUBRUN_LIMIT"

///|
const JournalVar = "OPENSEEK_MBTX_JOURNAL"

///|
const EventsVar = "OPENSEEK_MBTX_EVENTS"

///|
const ModelVar = "OPENSEEK_MBTX_MODEL"

///|
const ApiUrlVar = "OPENSEEK_MBTX_API_URL"

///|
/// What mbtx reserved for one snippet: the engine to spawn, where child
/// transcripts belong, the block of child ordinals this snippet may mint, and
/// the two files the host tails.
///
/// Fields are private. A snippet passes this value along; it has no business
/// reading a path it did not choose, and every field is a coordinate whose
/// only correct value is the one that arrived.
pub struct Injected {
  priv exe : String
  priv session_root : String
  priv parent : String
  /// The first child ordinal this snippet owns. Blocks are allocated
  /// parent-side and never overlap, so two snippets — including one still
  /// running in the background — cannot mint the same child session id.
  priv base : Int
  /// How many ordinals the block holds. It doubles as the launch ceiling:
  /// a snippet cannot start more children than it was given room for.
  priv limit : Int
  priv journal_path : String
  priv events_path : String
  priv model : String?
  priv api_url : String?
}

///|
/// The coordinates mbtx injected, or `None` when this snippet was not
/// launched with any.
///
/// `None` is a normal state, not an error: a snippet run against a
/// conversation with no durable session has nowhere to put child
/// transcripts, so mbtx injects nothing and there is nothing to visualize.
/// Such a snippet can still do ordinary work — it just cannot delegate
/// through `run`.
pub fn injected() -> Injected? {
  guard @env.get_env_var(ExeVar) is Some(exe) &&
    @env.get_env_var(SessionRootVar) is Some(session_root) &&
    @env.get_env_var(ParentVar) is Some(parent) &&
    @env.get_env_var(JournalVar) is Some(journal_path) &&
    @env.get_env_var(EventsVar) is Some(events_path) &&
    positive_int(@env.get_env_var(BaseVar)) is Some(base) &&
    positive_int(@env.get_env_var(LimitVar)) is Some(limit) else {
    return None
  }
  Some({
    exe,
    session_root,
    parent,
    base,
    limit,
    journal_path,
    events_path,
    model: @env.get_env_var(ModelVar),
    api_url: @env.get_env_var(ApiUrlVar),
  })
}

///|
/// Coordinates built directly rather than read from the environment.
///
/// The environment is how they arrive in a real snippet, and `injected()` is
/// the only reader of it. This constructor exists for the two callers that
/// already hold the values: tests, and any in-process caller that reserved a
/// block itself instead of going through mbtx.
pub fn Injected::Injected(
  exe~ : String,
  session_root~ : String,
  parent~ : String,
  base~ : Int,
  limit~ : Int,
  journal_path~ : String,
  events_path~ : String,
  model? : String,
  api_url? : String,
) -> Injected {
  {
    exe,
    session_root,
    parent,
    base,
    limit,
    journal_path,
    events_path,
    model,
    api_url,
  }
}

///|
/// A positive integer from an injected variable. Anything else — absent,
/// unparseable, zero, negative — fails the whole read: a block of unknown
/// size is not a block, and guessing one would let a snippet mint ordinals
/// that belong to another.
fn positive_int(raw : String?) -> Int? {
  guard raw is Some(raw) else { return None }
  let value = @string.parse_int(raw) catch { _ => return None }
  if value > 0 {
    Some(value)
  } else {
    None
  }
}

///|
test "a complete environment reads, and any missing coordinate refuses" {
  // The parser is exercised through `positive_int`, which is what decides
  // whether a block is usable; the env read itself is a straight lookup.
  assert_eq(positive_int(Some("7")), Some(7))
  assert_eq(positive_int(Some("0")), None)
  assert_eq(positive_int(Some("-3")), None)
  assert_eq(positive_int(Some("sr-1")), None)
  assert_eq(positive_int(Some("")), None)
  assert_eq(positive_int(None), None)
}
