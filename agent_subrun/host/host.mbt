// The openseek half of the host handoff: what a snippet is given so the
// children it delegates to are visible to the rest of the engine.
//
// `moonbitlang/workflow` is a generic library. It spawns whatever its `Runner`
// spawns and writes its journal wherever it was told, and it never learns
// openseek exists — so nothing a snippet can say about itself would make its
// children discoverable. The coordinates come from the host, chosen BEFORE the
// snippet runs and written into its environment as the library's own handoff,
// `WORKFLOW_HOST` (see `moonbitlang/workflow/hosted` and its
// docs/host-handoff.md). Discovery is therefore not discovery: a reader is told
// where to look, exactly as it is told that a sub-run started rather than
// finding one.
//
// This package knows what the sandbox tool that injects the handoff must not:
// the engine's own command line, the session store's layout, the child-session
// grammar `<parent>-sr-N`. It is a LEAF — `agent_subrun` builds one of these
// from a `ChildSession` and its shared allocator, and `mbtx` receives an
// opaque reservation and a variable to set; neither side's dependencies flow
// through here.

///|
/// How many child ordinals one snippet may mint.
///
/// It is a ceiling, not an estimate. A snippet is opaque to the parent — one
/// tool call can loop — so nothing else bounds how many children a confused
/// model can start from inside one, and goal runs execute unattended for
/// hours. Generous enough that a real fan-out never notices; small enough that
/// a runaway stops inside one call.
pub let block_size : Int = 32

///|
/// What to spawn, where transcripts belong, and the counter that keeps two
/// snippets from minting the same child id.
///
/// ABSTRACT: the layout is not the contract, and a caller has no business
/// reading a coordinate it did not choose.
struct SubrunInjection {
  exe : String
  session_root : String
  parent : String
  /// Where a child RUNS. Not the session store: an `explore` child reads the
  /// workspace by paths relative to its cwd, exactly as `run_subrun` launches
  /// it, and a store-rooted child would find nothing to read.
  workspace_root : String
  model : String?
  api_url : String?
  /// Reserve N consecutive child ordinals and return the first.
  reserve_ordinals : (Int) -> Int
}

///|
/// An injection over an explicit allocator.
///
/// `reserve_ordinals` must be the session's ONE child-ordinal allocator — the
/// counter `run_subrun` mints `explore` children from — or a snippet's child
/// and an `explore` child will be named alike and the second to append will
/// die against the first's stale snapshot. `ChildSession::injection` in
/// `agent_subrun` wires that counter; this package is a leaf and cannot name
/// it. Tests pass a local counter so ordinals do not depend on what earlier
/// tests in the process reserved.
///
/// `exe` must be absolute: a sandbox admits it by exact path, so parent and
/// child are the same binary and the report's derived JSON codecs cannot
/// drift — the guarantee `explore` gets by never resolving the engine through
/// `PATH`.
pub fn SubrunInjection::SubrunInjection(
  exe~ : String,
  session_root~ : String,
  parent~ : String,
  workspace_root~ : String,
  reserve_ordinals~ : (Int) -> Int,
  model? : String,
  api_url? : String,
) -> SubrunInjection {
  {
    exe,
    session_root,
    parent,
    workspace_root,
    model,
    api_url,
    reserve_ordinals,
  }
}

///|
/// The engine binary a snippet may spawn — what a sandbox policy admits, by
/// exact path, for the one delegating verb.
pub fn SubrunInjection::exe(self : SubrunInjection) -> String {
  self.exe
}

///|
/// One snippet's reserved coordinates: a disjoint block of child ordinals, the
/// directory holding the two files a reader tails for this run, and the guest
/// variable that carries them.
struct SubrunReservation {
  base : Int
  limit : Int
  dir : String
  journal_path : String
  events_path : String
  env : Map[String, String]
}

///|
/// The first child ordinal of the block.
pub fn SubrunReservation::base(self : SubrunReservation) -> Int {
  self.base
}

///|
/// How many ordinals the block holds — also the run's launch ceiling.
pub fn SubrunReservation::limit(self : SubrunReservation) -> Int {
  self.limit
}

///|
/// The run's OWN directory, and the one place in the session store a snippet
/// may write. A sandbox binds the guest's writes to explicit roots; granting
/// the whole store would let a snippet append to another session's
/// transcript, so the ledger gets a directory of its own instead. The
/// injecting tool creates it before naming it in a policy — moonrun refuses a
/// root that does not exist.
pub fn SubrunReservation::dir(self : SubrunReservation) -> String {
  self.dir
}

///|
/// The append-only ledger of RESOLVED calls: `<dir>/journal.jsonl`.
pub fn SubrunReservation::journal_path(self : SubrunReservation) -> String {
  self.journal_path
}

///|
/// The sidecar that reports a launch when it STARTS: `<dir>/events.jsonl`.
pub fn SubrunReservation::events_path(self : SubrunReservation) -> String {
  self.events_path
}

///|
/// The guest environment to set: `WORKFLOW_HOST` and nothing else.
pub fn SubrunReservation::env(self : SubrunReservation) -> Map[String, String] {
  self.env
}

///|
/// Reserve a block for one snippet invocation.
///
/// Blocks never overlap, so the child session ids two snippets mint cannot
/// collide — including a background snippet still running from an earlier
/// turn, which is the case a per-call counter would get wrong. The block base
/// also names the run's directory, so a caller that reserved a block knows the
/// paths without a second allocation.
///
/// The handoff is the workflow library's OWN contract, not an openseek one:
/// argv arrives as a template the library substitutes per call, so the
/// library never learns this engine's command line, and any other host can
/// write the same document. `attempt_id` in the resulting ledger is the
/// rendered `child_id` — `<parent>-sr-N` — which is exactly the session id the
/// transcript viewer links to and the desktop's progress probe tails.
pub fn SubrunInjection::reserve(self : SubrunInjection) -> SubrunReservation {
  let base = (self.reserve_ordinals)(block_size)
  // The run's directory lives in the session store's root, beside the store's
  // own `sessions/` tree that holds the transcripts it accounts for — with the
  // session data, not in a build directory that gets reclaimed. It is NOT
  // inside the store's tree: this package is a leaf and does not know the
  // store's private layout, and nothing enumerates the root itself, so the
  // ledger is found only by the paths announced for it, never by walking.
  let dir = "\{self.session_root}/\{self.parent}-wf-\{base}"
  let journal_path = "\{dir}/journal.jsonl"
  let events_path = "\{dir}/events.jsonl"
  // The child argv, with the library's two placeholders. The API key NEVER
  // rides argv — it reaches the child through the inherited environment.
  // Per-call `max_steps` is not here either: it rides the request envelope,
  // where the contract already carries it, and `subrun` reads it from there.
  let child_args = ["subrun", "{kind}"]
  if self.model is Some(model) {
    child_args.push("--model")
    child_args.push(model)
  }
  if self.api_url is Some(url) {
    child_args.push("--api-url")
    child_args.push(url)
  }
  child_args.push("--session")
  child_args.push("{child}")
  child_args.push("--session-root")
  child_args.push(self.session_root)
  let handoff : Json = {
    "v": 1,
    "exe": self.exe,
    "child_args": Json(child_args.map(Json::string)),
    "child_id": "\{self.parent}-sr-{n}",
    "ids": [
      Json::number(base.to_double()),
      Json::number(block_size.to_double()),
    ],
    "journal": journal_path,
    "events": events_path,
    "cwd": self.workspace_root,
  }
  {
    base,
    limit: block_size,
    dir,
    journal_path,
    events_path,
    env: { "WORKFLOW_HOST": handoff.stringify() },
  }
}
