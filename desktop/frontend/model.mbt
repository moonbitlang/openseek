///|
const DefaultModel : String = "deepseek-v4-pro"

///|
/// Viewports at most this wide (CSS pixels) get the narrow layout. Must
/// match the `@media (max-width: …)` breakpoint in index.html.
const NarrowBreakpoint : Int = 760

///|
const DefaultMaxSteps : String = "1000"

///|
const TranscriptRefreshFailedNotice : String = "Transcript refresh failed repeatedly. New commits are buffered; reopen the conversation or wait for the next update to retry."

///|
/// Legacy localStorage keys from when the page stored the engine endpoint
/// settings itself. Those now live on the host (`settings.get`/`set`); the
/// keys remain only so the desktop window can migrate stored values up once
/// and every page can purge the leftover secrets.
const LegacyApiKeyStorageKey : String = "openseek.deepseek_api_key"

///|
const LegacyCustomApiKeyStorageKey : String = "openseek.custom_api_key"

///|
const LegacyApiProviderStorageKey : String = "openseek.api_provider"

///|
const LegacyCustomApiUrlStorageKey : String = "openseek.custom_api_url"

///|
const LegacyWslEnabledStorageKey : String = "openseek.wsl_enabled"

///|
const LegacyWslDistroStorageKey : String = "openseek.wsl_distro"

///|
const LegacyWslEngineStorageKey : String = "openseek.wsl_engine"

///|
const NotificationCornerStorageKey : String = "openseek.notification_corner"

///|
/// Where the editor panel's file tree docks (bottom panel / right sidebar).
const TreeLayoutStorageKey : String = "openseek.tree_layout"

///|
/// Obsolete: the update channel derives from the server selection now. The
/// key is kept only so startup can delete whatever old builds stored.
const UpdateChannelStorageKey : String = "openseek.update_channel"

///|
/// Which chat-completions endpoint the engine talks to. `Openseek` is the
/// zero-config default — the proxy does not validate API keys. `Deepseek` is
/// the official endpoint and needs the user's own key. `Custom` is any other
/// DeepSeek-compatible endpoint; whether it needs a key is the endpoint's
/// business, so the key is optional there. The setting (and its
/// credentials) live on the host; this mirror is what `settings.get`/`set`
/// replies and the `settings.changed` broadcast last reported.
priv enum ApiProvider {
  Openseek
  OpenseekStaging
  Deepseek
  Custom
} derive(Eq)

///|
fn ApiProvider::wire(self : ApiProvider) -> String {
  match self {
    Openseek => "openseek"
    OpenseekStaging => "openseek-staging"
    Deepseek => "deepseek"
    Custom => "custom"
  }
}

///|
/// Unknown stored values fall back to the default provider, so a downgrade
/// (or a corrupted store) degrades to the zero-config endpoint instead of
/// wedging the app.
fn ApiProvider::parse(value : String) -> ApiProvider {
  match value.trim().to_owned() {
    "openseek-staging" => OpenseekStaging
    "deepseek" => Deepseek
    "custom" => Custom
    _ => Openseek
  }
}

///|
/// The update channel the server selection implies: the staging server
/// serves staging builds, everything else follows production. The channel
/// stopped being its own setting when the server choice became one.
fn ApiProvider::update_channel(self : ApiProvider) -> UpdateChannel {
  match self {
    OpenseekStaging => Staging
    Openseek | Deepseek | Custom => Production
  }
}

///|
/// The compaction lifecycle of one conversation, mirroring the host's
/// `EnginePhase` design: one value instead of loose booleans, so a compact
/// request that is in flight but not yet acknowledged still has a
/// representation — every phase but `NotCompacting` holds the send gate and
/// shows a composer notice, and a request the model forgot to track cannot
/// exist. Settled by the engine's `compaction_*` events, or by
/// `CompactRejected` when the request never reached one.
priv enum CompactionPhase {
  // Nothing pending; the only phase that accepts a `/compact`.
  NotCompacting
  // Requested while idle: the op is on the wire and the host may still be
  // spawning a serve engine for it (a resumed conversation compacted before
  // its first prompt — seconds, not milliseconds). `compaction_started`
  // confirms it.
  Requested
  // Requested mid-turn: the engine queues it behind the open run, so this
  // holds the gate through the gap between the turn's end and the queued
  // compaction's start.
  Queued
  // The engine reported `compaction_started` and has not yet reported the
  // summary or a failure.
  Compacting
} derive(Eq)

///|
/// The run lifecycle of one conversation, as a single value: the old
/// `running`/`active_run_id`/`status` trio encoded the same facts three ways
/// and let them drift ("running with no id yet" was Starting only by
/// convention; a status of Running with the flag down was expressible).
/// Every gate reads this one field, so a phase the model forgot to track
/// cannot exist.
priv enum RunPhase {
  // Between runs; `ended` remembers how the last one closed (`None` before
  // the first run of this app-lifetime).
  NoRun(ended~ : RunEnd?)
  // Send accepted: this exact submission's start op is in flight and no run
  // id exists yet. Keeping the id in the phase prevents an older reconnect
  // snapshot from adjudicating a newer start merely because both ids remain
  // in the reconciliation ledger.
  Starting(submission_id~ : String)
  // The host's `started` event opened run `run_id`.
  Open(run_id~ : String, stage~ : TurnStage)
} derive(Eq)

///|
/// How far an open turn has progressed — one axis, like the old status
/// column: a Stop overwrites the step display with "Cancelling" and stays
/// there (steering a dying turn is refused, so a later step must not flip
/// the gate back open).
priv enum TurnStage {
  // `started` arrived, no step event yet.
  Opened
  // The engine's latest 1-based step counter (`None` from engines that do
  // not number their steps).
  AtStep(Int?)
  // A Stop was sent and the engine has not yet honored it.
  Cancelling
} derive(Eq)

///|
/// How a finished run closed, kept for the topbar/sidebar after the run
/// phase returns to `NoRun`.
priv enum RunEnd {
  RunFailed
  RunErrored
  RunFinished(RunOutcome)
} derive(Eq)

///|
/// One run identity returned by an `agent.runs` snapshot. The whole snapshot
/// crosses into `update` as one generation-tagged message, so a reply from an
/// older connection cannot replay any of these starts into a newer model.
priv struct RecoveredRun {
  run_id : String
  session : String
  model : String
  max_steps : Int
  cwd : @pathx.Absolute?
  session_root : @pathx.Absolute?
  task : String?
  submission_id : String?
}

///|
/// One completed lifecycle returned by `agent.runs` for an exact owner the
/// reconnecting page named. These rows are process-lifetime host evidence,
/// not a history feed: selector matching below prevents an old completion
/// from settling a newer run that reused the same conversation UI.
priv struct RecoveredSettlement {
  run_id : String
  session : String
  submission_id : String?
  status : String
  durable_sequence : Int?
}

///|
/// The exact per-session lifecycle state at the instant an `agent.runs`
/// request starts. An unversioned positive row is safe to replay only while
/// the session still has this state; a live Started or Finished received
/// meanwhile takes precedence over the older snapshot. `steer_ids` freezes
/// the local inputs that existed at that same cut, so a slower negative reply
/// cannot adjudicate a steer submitted after the request began.
priv enum RunSnapshotState {
  SnapshotIdle(last_run_id~ : String?)
  SnapshotStarting(submission_id~ : String)
  SnapshotOpen(run_id~ : String)
}

///|
priv struct RunSnapshotFrontier {
  session : String
  state : RunSnapshotState
  // Initial prompts whose start transport failed before a run id came back.
  // Their submission id is still an exact owner and must survive the
  // lifecycle's transition to SnapshotIdle for reconnect settlement lookup.
  initial_ids : Array[String]
  steer_ids : Array[String]
}

///|
/// How a recovered settlement matched the request-time owner. Submission
/// matches must first bind the host's run id into the local input ledger;
/// run matches already have that identity.
priv enum SettlementFrontierMatch {
  SettlementByRun
  SettlementBySubmission(String)
}

///|
/// One conversation's full client-side state. Each conversation maps to a
/// durable engine session and, while running, to its own `--serve` engine
/// process in the host — several conversations can run turns concurrently,
/// so everything a run touches lives here rather than on the model.
priv struct Conversation {
  // The device channel this conversation lives on. Its transcript, runs,
  // and every op it issues belong to that channel; two devices may hold
  // the same session id without aliasing.
  device : @interop.ChannelId
  // Durable engine session backing this conversation; consecutive runs share
  // it so the agent keeps context between prompts.
  session_id : String
  // The project directory this conversation is attached to, `None` for a
  // scratch conversation in the app-managed workspace. Sent with every start
  // so the engine runs in the project and stores the session inside it. Also
  // one of the two roots (`cwd` first) a legacy absolute chip path is
  // relativized against before a jump.
  workspace : @pathx.Absolute?
  // Composer draft, kept per conversation so switching away (and back)
  // neither loses the text nor sends it to the wrong session.
  task : String
  // Mention chips attached to the draft (`$` skills, `#` symbols), part of the
  // draft and so likewise per conversation. Expanded into the prompt on send,
  // then cleared with the text.
  mentions : Array[Mention]
  // Where this conversation's run stands; see `RunPhase`. Replaces the old
  // `running`/`active_run_id`/`status` trio, whose redundant encodings could
  // drift apart (running with no id was "starting" only by convention).
  run : RunPhase
  // The most recent run id this conversation has owned, kept after the run
  // finishes. Compaction is requested while the engine is idle, so its
  // engine events arrive stamped with this id once the run phase is already
  // back to `NoRun`; routing them needs the retained id.
  last_run_id : String?
  // Highest durable terminal sequence already known for this conversation.
  // A locally steerable run freezes its own floor at start; a later terminal
  // can therefore be recognized even if its commit beats `Finished` to UI.
  last_terminal_sequence : Int
  // Exclusive lower bound for the current run's terminal. `None` means the
  // run began while transcript history was unresolved; steering stays gated
  // rather than attaching a local notice to an unprovable boundary.
  run_durable_floor : Int?
  // The first snapshot generation issued after a foreign Started. An older
  // in-flight snapshot may drain commits but cannot establish the new run's
  // floor; only this causal read (or a later one) may release commit-based
  // floor discovery.
  run_floor_generation : Int?
  // Where this conversation's compaction stands; see `CompactionPhase`.
  compaction : CompactionPhase
  // A run finished while this conversation was off screen and the user has
  // not looked since: the sidebar's running pulse settles into a solid dot
  // (accent for success, warn otherwise) until the conversation is opened.
  unseen_finish : Bool
  usage_tokens : Int
  // The conversation's workspace directory as reported by the host's
  // `started` event — `None` until the first run reports it. Display
  // (topbar tooltip), the working directory for `open_path`/`launch_app`,
  // and the preferred root for relativizing a legacy absolute chip path;
  // the host derives it from the session id, so it is never sent back with
  // a start request.
  cwd : @pathx.Absolute?
  // The git branch checked out in the workspace, reported by the host's
  // `workspace_branch` op — display only (topbar chip). `None` until a probe
  // answers (or when it fails); `Some("")` when the workspace is not a
  // repository. Either way the chip hides. Refreshed when a run starts, a
  // stored session opens, and a run finishes.
  branch : String?
  watcher_status : String
  // Live text of the in-flight assistant turn, accumulated from
  // `assistant_delta` events and cleared by ordered full semantic, step,
  // run-lifecycle, or reconnect boundaries. Follower commits are not run/step
  // tagged and therefore never clear a potentially newer stream. Empty means
  // not streaming.
  streaming_response : String
  // Local submissions awaiting exact id-bearing host receipts. Initial prompt
  // and steer entries share the ledger; steer state is also the sole source
  // for pending UI and provisional failures. Canonical User text never claims
  // ownership, so identical submissions from multiple clients cannot collide.
  input_ledger : Array[PendingInput]
  // The durable transcript: exactly what `session.load` snapshots and
  // `session.event` commits said, nothing else. Copy-on-write.
  messages : Array[@transcript.TranscriptItem]
  // The highest durable sequence `messages` reflects: commits at or below it
  // are already applied, `watermark + 1` applies next, and anything later is
  // a gap — this client missed a broadcast — answered by a reload.
  watermark : Int
  // Where the durable transcript stands relative to the store; see
  // `TranscriptSync`.
  sync : TranscriptSync
  // Client-local transcript notices with no durable counterpart (a rejected
  // start, a dropped steer, a repeatedly failed transcript refresh). Each is
  // anchored to a durable chronology boundary, so later turns render after it
  // rather than pushing an old notice to the transcript tail. A run-end steer
  // failure follows the current tail only until the durable terminal boundary
  // arrives; some delivery failures are provisional and a later exact-id
  // receipt can retract them. Copy-on-write.
  overlay : Array[LocalNotice]
} derive(Eq)

///|
/// How a local notice may be reconciled by a later canonical User. Start RPC
/// and steer delivery failures are indeterminate: the host may have accepted
/// the submission before its response path failed. Only the exact id-bearing
/// receipt may retract one; transcript text is deliberately not ownership.
priv enum NoticeReconciliation {
  Retained
  Submission(String)
  RunDiagnostic(String)
} derive(Eq)

///|
/// Where a client-local notice sits in the durable chronology. `TerminalTail`
/// waits for a run whose semantic finish guarantees a durable Terminal.
/// Once another run starts, only a causal full snapshot may locate that old
/// terminal: its commit may already have passed before the notice existed, so
/// a later live terminal could belong to the successor. `SnapshotCut` waits
/// for a full read started after the uncertain lifecycle transition, then
/// fixes the notice at that read's display boundary without claiming any item
/// inside it. Bare `UncertainTail` has neither a terminal nor a scheduled cut
/// and therefore never claims an anonymous durable event. `DurableTail` names
/// an exact final sequence learned from the host's EOF scan.
priv enum NoticeAnchor {
  AfterMessages(Int)
  TerminalTail(Int?)
  PriorTerminalTail(floor~ : Int, snapshot_generation~ : Int)
  SnapshotCut(snapshot_generation~ : Int)
  UncertainTail
  DurableTail(Int)
} derive(Eq)

///|
priv enum InputKind {
  InitialPrompt
  SteerInput
} derive(Eq)

///|
priv enum InputState {
  Awaiting
  Unconfirmed
} derive(Eq)

///|
/// One locally submitted input awaiting an id-bearing host receipt. The
/// globally unique `submission_id` is the only ownership proof: canonical
/// transcript text and legacy receipts without an id never settle this entry.
/// The original draft shape is retained so a definitive refusal can restore
/// it to the composer without exposing the serialized mention envelope.
priv struct PendingInput {
  submission_id : String
  kind : InputKind
  // The run this input belongs to once Started or the start response supplies
  // it. Initial prompts begin as `None`; retaining their draft until a normal
  // durable finish (not merely an stdin-write response) prevents pre-append
  // engine failures from losing the user's text.
  run_id : String?
  content : String
  draft : String
  mentions : Array[Mention]
  state : InputState
} derive(Eq)

///|
/// One non-durable transcript notice at a durable chronology boundary.
priv struct LocalNotice {
  kind : @transcript.ItemKind
  content : String
  anchor : NoticeAnchor
  reconciliation : NoticeReconciliation
} derive(Eq)

///|
/// Whether the conversation's durable transcript is up to date with the
/// store, a generation-tagged re-read is in flight, or a bounded retry round
/// has stopped. Commits stay buffered across every failure. A later commit,
/// reconnect, or explicit open starts a fresh generation from `ReloadFailed`.
priv enum TranscriptSync {
  Synced
  Reloading(
    generation~ : Int,
    attempt~ : Int,
    buffered~ : Array[BufferedCommit],
    // A durable boundary arrived after this request started. Keep the read
    // single-flight, then run one more generation so an older in-flight
    // snapshot cannot become the final view of that boundary.
    reload_after_current~ : Bool
  )
  ReloadFailed(generation~ : Int, buffered~ : Array[BufferedCommit])
} derive(Eq)

///|
priv struct BufferedCommit {
  sequence : Int
  kind : String
  payload : Map[String, Json]
} derive(Eq)

///|
/// What the main area shows: the active conversation, the Skills page, or
/// the Settings page. Selecting a conversation (or rotating to a new one)
/// always returns to the chat. Settings also opens on its own while the
/// configured endpoint is unusable, since the composer would be dead weight.
priv enum Screen {
  Chat
  Skills
  Settings
} derive(Eq)

///|
/// Which trigger opened the composer's completion menu: `/` lists built-in
/// commands that act on the conversation, `$` lists installed skills whose
/// name is inserted into the prompt, `#` lists workspace symbols (fetched from
/// the conversation's language server) whose reference is inserted.
priv enum CompletionKind {
  SlashCommands
  SkillMentions
  Symbols
} derive(Eq)

///|
/// One row of the composer completion menu.
priv struct CompletionItem {
  // The primary label shown in the row (e.g. "/compact" or "$review-pr").
  label : String
  // A short description shown next to the label.
  detail : String
  // For a slash command, the id its accepted action dispatches on; empty for
  // skills. For a skill, `insert` carries the text dropped into the composer.
  command : String
  insert : String
  // A symbol row's resolved location — workspace-relative path and the
  // symbol's full range (one-based, viewer coordinates) — so the chip it
  // becomes can jump there and select the named code. `None` for slash
  // commands, skills, and symbols the language server could not place in a
  // file. A server that placed the symbol without a range yields an empty
  // range anchored at its line.
  path : String?
  range : @common.Range?
} derive(Eq)

///|
/// One accepted mention, shown as a chip above the composer and folded into
/// the outgoing prompt's `<user_mentions>` envelope on send. `ref` is the
/// envelope form itself (`$` skill, `#` symbol, or an editor comment) — the
/// single source for the chip's glyph/label/jump target (`mention_chip`) and
/// for dedup. `range` keeps the full resolved range the envelope's
/// `file:line` cannot carry, so a draft chip's jump still selects the exact
/// span (`None` for a skill or an unplaced symbol).
priv struct Mention {
  ref_ : @mention_context.MentionRef
  range : @common.Range?
} derive(Eq)

///|
/// The composer's open completion menu: the trigger that opened it, the
/// currently matching rows, which row is highlighted, and the exact draft text
/// before the live token. Absent when the composer has no live trigger.
/// `loading` is set only for a `#` menu whose results for the current query have
/// not arrived yet, so the empty menu can say "Searching…" rather than
/// "No symbols".
priv struct Completion {
  kind : CompletionKind
  items : Array[CompletionItem]
  selected : Int
  loading : Bool
  task_without_token : String
} derive(Eq)

///|
/// The last workspace-symbol results, cached so the `#` menu can show them
/// without refetching while the query is unchanged. `session` records which
/// conversation they belong to, so switching either device or session
/// refetches rather than showing another workspace's symbols; `query` is the
/// trigger text they answer, the key that decides whether a keystroke needs a
/// fresh fetch.
priv struct SymbolCache {
  owner : @interop.ConversationKey?
  query : String
  items : Array[CompletionItem]
} derive(Eq)

///|
fn empty_symbol_cache() -> SymbolCache {
  { owner: None, query: "", items: [] }
}

///|
/// The mooncakes.io skill catalog as the Skills page sees it. One enum, so
/// "loading", "loaded empty" and "failed" cannot be conflated.
priv enum SkillsCatalog {
  CatalogIdle
  CatalogLoading
  CatalogReady(Array[@transcript.MarketSkillItem])
  CatalogFailed(String)
} derive(Eq)

///|
/// Whether the host bridge is up — three states the old `bridge_ready` bool
/// plus "why not" string encoded with an empty-string sentinel: still
/// probing for the injected bridge, connected, or given up with a reason.
priv enum BridgeState {
  Connecting
  Connected
  BridgeLost(String)
} derive(Eq)

///|
/// The latest identity-bearing archive fact this connection observed for one
/// session. Whole-list replies do not carry a revision and can predate that
/// notification, so they are reconciled through this override until the next
/// connection boundary starts a fresh authoritative list round.
priv struct ArchiveOverride {
  session : String
  archived : Bool
} derive(Eq)

///|

///|
/// Everything that exists once per connected device channel. The app holds
/// one entry per channel in `Model::devices` — exactly one today (the page's
/// own host); the multi-device console renders one sidebar group per entry.
priv struct DeviceState {
  // The channel this state mirrors.
  channel : @interop.ChannelId
  // Whether the channel's host bridge is up; see `BridgeState`.
  bridge : BridgeState
  // Consecutive WebSocket losses since the last successful connection.
  // Drives the reconnect backoff and the BridgeLost threshold; always 0 for
  // the proton channel, whose bridge never reconnects.
  reconnect_failures : Int
  // Incremented at every BridgeReady. Session-list replies carry the value
  // captured when their request was issued, so a reply from a dead connection
  // cannot overwrite the lists rebuilt after reconnect.
  connection_generation : Int
  // Page-lifetime request tokens for the independently fetched sidebar
  // collections. Connection generation rejects dead sockets; these reject an
  // older reply from the same connection after a newer request was issued.
  sessions_request_generation : Int
  archived_request_generation : Int
  workspaces_request_generation : Int
  // Durable sessions known to the engine's store, newest first, refreshed
  // when the bridge connects and when a run reaches the store. A new
  // conversation appears here once its first turn has been persisted.
  sessions : Array[@transcript.SessionListItem]
  // Conversations the host has archived (durable record moved into the
  // store's `archived` twin); the sidebar tucks their rows under a collapsed
  // "Archived" group with an unarchive control. Reported by the host in the
  // same entry shape as the live list.
  archived : Array[@transcript.SessionListItem]
  // Per-session archive facts newer than an unversioned whole-list reply.
  // Cleared only at BridgeReady, immediately before fresh live and archived
  // lists are requested for the new connection.
  archive_overrides : Array[ArchiveOverride]
  // Project directories attached as workspaces: the host registry's absolute
  // paths in registration order. The sidebar shows one section per entry.
  workspaces : Array[String]
  // Where "New chat" lands: a registered workspace path, or "" for the
  // default scratch store. Follows the conversation last opened or created.
  active_workspace : String
} derive(Eq)

///|
fn empty_device_state(channel : @interop.ChannelId) -> DeviceState {
  {
    channel,
    bridge: Connecting,
    reconnect_failures: 0,
    connection_generation: 0,
    sessions_request_generation: 0,
    archived_request_generation: 0,
    workspaces_request_generation: 0,
    sessions: [],
    archived: [],
    archive_overrides: [],
    workspaces: [],
    active_workspace: "",
  }
}

///|
priv struct Model {
  // Connected device channels in stable order: the desktop window's one
  // Local host, or a browser console's roster devices — empty there until
  // the roster loads (`apply_roster`).
  devices : Array[DeviceState]
  // The device channel every UI action targets — the Settings/Skills
  // screens, the composer, and the active conversation. The desktop window
  // is born with `Local`; a browser console starts on an inert `Local`
  // default that nothing reads and focuses a device with its first roster.
  focused : @interop.ChannelId
  selected_model : String
  max_steps : String
  // Whether the host has a key stored for each keyed provider. The key text
  // itself never reaches a client — the Settings page only needs presence
  // (placeholder wording, the ready gate); a new key is staged in
  // `setup_api_key` until saved through `settings.set`.
  deepseek_key_saved : Bool
  custom_key_saved : Bool
  setup_api_key : String
  // Which endpoint the engine talks to; `custom_api_url` only matters when
  // the provider is `Custom`. Both mirror the host's settings store and are
  // edited through `settings.set`.
  api_provider : ApiProvider
  custom_api_url : String
  // Host-settings writes still in flight. While any are, incoming
  // `settings.changed` broadcasts and `settings.get` replies may predate an
  // optimistic edit, so the newest revision is deferred until the last write
  // settles instead of clobbering the form mid-edit.
  settings_saves : Int
  // Host-local monotonic revision attached to every settings status. It
  // orders concurrent clients' broadcasts and RPC replies; -1 means this
  // bridge generation has not accepted an authoritative status yet.
  host_settings_revision : Int
  deferred_host_settings : HostSettings?
  // A legacy localStorage migration's push is in flight; its success is
  // what deletes the migrated secrets from localStorage.
  legacy_cleanup_pending : Bool
  // Run the serve engine inside WSL instead of natively. Windows-host-only:
  // `host_wsl` (the host's own capability, from `host.meta` at bridge time —
  // the page may run on any device while the engine runs on the host) gates
  // both the settings section and what `start` sends. `wsl_distro` empty
  // means the user's default distro; `wsl_engine` empty means `openseek` on
  // the distro's PATH. The host settings store persists all three and shares
  // them with every attached client.
  host_wsl : Bool
  // Whether this page is the desktop window (the proton webview) rather than
  // a browser reached through a relay. Probed once at startup. Gates the
  // self-update flow: applying an update swaps the
  // bundle under the desktop process and relaunches through the window's
  // close path — from a browser tab, `window.close()` exits nothing, and the
  // update would yank the app out from under whoever is at the machine.
  is_desktop : Bool
  // A browser page's account layer: the relay session and the device
  // roster (see `ConsoleState`). None in the desktop window, whose one
  // Local channel needs no account and no roster.
  console : ConsoleState?
  wsl_enabled : Bool
  wsl_distro : String
  wsl_engine : String
  // Whether the host prefers a dark color scheme. The app's own palette
  // follows `prefers-color-scheme` in CSS; this mirror drives the embedded
  // viewer's `data-theme` attribute, which CSS media queries cannot set.
  // Seeded at startup and kept fresh by `watch_color_scheme`.
  dark_mode : Bool
  // Whether the viewport is phone-narrow (at most `NarrowBreakpoint` wide).
  // Seeded from the window at startup and kept fresh by the resize
  // subscription; the value must agree with index.html's one mobile media
  // query, so layout-dependent behavior (the sidebar drawer, the file
  // panel's drill-down) flips exactly where the CSS does.
  narrow : Bool
  // Whether the left sidebar (chat list + navigation) is shown. Collapsing it
  // hands the full width to the conversation; the topbar toggle brings it back.
  // On the narrow layout the sidebar is a full-screen drawer instead of a
  // column, and starts closed.
  sidebar_open : Bool
  // Whether the sidebar's "Chats" section (the default store's loose
  // conversations) is folded down to its heading; clicking the heading flips
  // it.
  chats_collapsed : Bool
  // Whether the sidebar's "Workspaces" section (the attached projects and their
  // nested conversations) is folded down to its heading; clicking the heading
  // flips it.
  workspaces_collapsed : Bool
  // The conversation on screen; always present in `conversations` once the
  // startup session rotation lands.
  active_session : String
  // Durable conversation currently being fetched from its host, if any.
  // Sidebar selections can race across devices; only the latest full identity
  // may activate a stored conversation.
  loading_conversation : @interop.ConversationKey?
  // Last token allocated to a transcript snapshot request in this app run.
  // This lives above individual conversations so pruning, archive removal,
  // and reopening cannot reuse a token that an older host reply still carries.
  transcript_request_generation : Int
  // A page-lifetime namespace plus monotonic counter allocate globally unique
  // submission ids without making `update` read randomness. Different windows
  // get independent timestamp/random namespaces; replaying the same model is
  // deterministic.
  submission_namespace : String
  submission_sequence : Int
  // Every conversation with live client state this app run: the active one,
  // those still running in the background, and those visited and kept for an
  // instant switch back. Copy-on-write, like the transcript arrays.
  conversations : Array[Conversation]
  // The in-app folder picker behind "Add a workspace"; None while closed.
  workspace_picker : WorkspacePicker?
  // Whether the transcript is scrolled to its bottom. Streaming output only
  // auto-follows while this holds — scrolling up to read history must not be
  // yanked back down by the next delta. Maintained by a DOM scroll watcher;
  // explicit user actions (sending, switching conversations) re-pin it.
  transcript_pinned : Bool
  // The Skills page: the registry catalog, the local library's contents,
  // the search filter, entries with an install/uninstall in flight (keyed
  // by the catalog entry's source label or the installed entry's id), and
  // the last failure to show. The catalog is fetched when the page opens
  // and kept for the app run; the installed list refreshes on open and
  // after every successful action.
  screen : Screen
  skills_catalog : SkillsCatalog
  installed_skills : Array[@transcript.InstalledSkillItem]
  skills_query : String
  skills_busy : Array[String]
  skills_notice : String
  // The composer completion menu, open only while the active conversation's
  // draft begins with a `/` or `$` trigger. Lives on the model rather than the
  // conversation: it is transient UI for the on-screen composer, recomputed on
  // every keystroke and dismissed on blur, send, or conversation switch.
  completion : Completion?
  // The last `#` symbol search's results, kept so the menu shows instantly
  // while the query is unchanged. Recomputed on every keystroke and refetched
  // when the query or conversation changes.
  symbol_cache : SymbolCache
  // The desktop topbar's app launcher. Installed apps belong to the native
  // host, not a conversation or workspace, so this catalog is probed once
  // and kept while the frontend runs.
  launcher : Launcher
  // The editor side-panel: the active conversation's file tree and the file
  // shown in the embedded viewer. Rooted at `active().cwd`; rebuilt when the
  // active conversation changes. Owned by the `fileeditor` package; this
  // model only carries its state and routes `FileEditor` messages to it.
  file_panel : @fileeditor.State
  // Transient error toasts, oldest first, and the id the next toast will
  // take. Ids only ever grow, so a toast's auto-dismiss timer can never
  // collide with a later toast.
  notifications : Array[Notification]
  notification_seq : Int
  // Which window corner toasts pop up in; a Settings choice, persisted.
  notification_corner : NotificationCorner
  // Where the editor panel's file tree docks; a Settings choice, persisted.
  tree_layout : @fileeditor.TreeLayout
  // Where the self-update flow stands, from "never checked" through the
  // download to the restart. One enum, so "checking", "downloading" and
  // "confirming" cannot overlap. (The channel it checks derives from the
  // server selection — `ApiProvider::update_channel`.)
  update_ux : UpdateUx
  // The host's relay sign-in mirror (`auth.status` reply / `auth.changed`
  // broadcast), None until the first reply. Desktop-window-only UI.
  remote_access : RemoteAccess?
  // An `auth.connect` waiting on the user's browser round-trip.
  remote_connecting : Bool
  // The last connect/disconnect failure, shown inside the section.
  remote_error : String?
} derive(Eq)

///|
/// One `auth.status`/`auth.changed` payload, decoded: who this host is
/// signed in as and whether its relay registration is live. A mirror of
/// the wire shape (docs/remote-protocol.md `auth.*`) — signed out is
/// `user_login: None`.
priv struct RemoteAccess {
  server_url : String?
  connected : Bool
  managed_by_env : Bool
  user_login : String?
  device_name : String?
  device_url : String?
} derive(Eq)

///|
/// The desktop topbar app launcher's state: whether its menu is open and the
/// Local native host's process-wide installed-app catalog.
priv struct Launcher {
  open : Bool
  apps : LauncherApps
} derive(Eq)

///|
/// The in-app folder picker's state: the host directory currently shown,
/// its parent (None at the filesystem root), its subdirectories, and the
/// editable path field. `loading` marks a browse in flight; `error` keeps a
/// failed navigation's message beside the previous listing, which stays
/// usable. `channel` owns every browse and the eventual workspace mutation;
/// `generation` numbers that picker's latest request. Both ride on replies,
/// so neither a superseded navigation nor a closed picker from another
/// device can replace the current listing.
priv struct WorkspacePicker {
  channel : @interop.ChannelId
  path : String
  entries : Array[String]
  input : String
  loading : Bool
  error : String?
  generation : Int
} derive(Eq)

///|

///|
/// A picker that just opened: nothing browsed yet, first listing (the home
/// directory) on its way.
fn opening_workspace_picker(channel : @interop.ChannelId) -> WorkspacePicker {
  {
    channel,
    path: "",
    entries: [],
    input: "",
    loading: true,
    error: None,
    generation: 1,
  }
}

///|
/// The Local native host's installed-app catalog. `AppsLoading` makes the
/// probe single-flight: closing and reopening the menu cannot start another
/// request while the first is still running.
priv enum LauncherApps {
  AppsNotFetched
  AppsLoading
  AppsFetched(Array[@transcript.LauncherAppItem])
  AppsFailed(String)
} derive(Eq)

///|
/// One `settings.get`/`settings.set` reply (or `settings.changed`
/// broadcast), decoded: the host's engine endpoint settings, with key
/// material reduced to presence.
priv struct HostSettings {
  revision : Int
  provider : String
  custom_api_url : String
  has_deepseek_key : Bool
  has_custom_key : Bool
  wsl_enabled : Bool
  wsl_distro : String
  wsl_engine : String
} derive(Eq)

///|
priv enum Msg {
  Init
  // The browser console's account layer (relay session, device roster),
  // routed through `update_console_msg`.
  Console(ConsoleMsg)
  // UI preferences read back from localStorage at startup. Engine endpoint
  // settings are the host's (`HostSettingsLoaded`); only page-local looks
  // live here.
  SettingsLoaded(notification_corner~ : String, tree_layout~ : String)
  // The legacy localStorage engine settings, read at bridge time. The
  // desktop window migrates them up to the host once; a browser page only
  // purges them (a stale secret in shared storage is the leak this design
  // removes).
  LegacySettingsRead(
    provider~ : String,
    custom_url~ : String,
    api_key~ : String,
    custom_api_key~ : String,
    wsl_enabled~ : String,
    wsl_distro~ : String,
    wsl_engine~ : String
  )
  TaskChanged(String)
  // Move the completion menu's highlight by a delta (−1 up, +1 down), wrapping
  // at the ends. Ignored when the menu is closed.
  CompletionMove(Int)
  // Accept the highlighted completion: run the slash command or insert the
  // skill mention into the composer.
  CompletionAccept
  // Accept a specific completion row by index, for a mouse click on the menu.
  CompletionPick(Int)
  // Close the completion menu without acting (Escape, or a click away).
  CompletionDismiss
  // Remove a mention chip from the active conversation's draft, by index.
  RemoveMention(Int)
  // Jump the editor side-panel to a mention chip's resolved location, by
  // index. A no-op for a chip with no `path` (a skill, or an unresolved
  // symbol).
  JumpToMention(Int)
  // Jump the editor side-panel to a transcript chip's resolved location — a
  // sent message's mention, parsed back out of its `<user_mentions>` envelope,
  // so it carries the location itself rather than a draft index. The path is
  // the envelope's raw text: workspace-relative for chips minted since the
  // panel started recording relative names, possibly absolute in a legacy
  // envelope — `open_editor_at` classifies and relativizes. `range` is the
  // chip's line span (the envelope stores no columns); an annotation chip
  // also carries its comment text, re-shown as an editor bubble over that
  // range.
  JumpToLocation(path~ : String, range~ : @common.Range?, annotation~ : String?)
  // A `workspace_symbols` reply: `owner`/`query` say which request it answers
  // so a reply that lost a device/session switch or later keystroke is dropped.
  SymbolsLoaded(
    owner~ : @interop.ConversationKey,
    query~ : String,
    items~ : Array[CompletionItem]
  )
  // A failed search reads as "no symbols", so it carries no message to show —
  // only the `owner`/`query` needed to settle the right menu.
  SymbolsFailed(owner~ : @interop.ConversationKey, query~ : String)
  ModelChanged(String)
  MaxStepsChanged(String)
  SetupApiKeyChanged(String)
  ProviderChanged(String)
  CustomApiUrlChanged(String)
  // The engine-environment select ("native"/"wsl") and the WSL text fields.
  WslModeChanged(String)
  WslDistroChanged(String)
  WslEngineChanged(String)
  // The Settings choice of which window corner error toasts pop up in.
  NotificationCornerChanged(String)
  // The Settings choice of where the editor's file tree docks.
  TreeLayoutChanged(String)
  // A toast's lifetime elapsed; drops it unless a click already did.
  NotificationExpired(Int)
  // A toast was clicked: dismiss it now.
  DismissNotification(Int)
  // The Settings "Check for updates" button.
  CheckForUpdates
  // An `auth.status` reply or `auth.changed` broadcast: the host's relay
  // sign-in state moved.
  RemoteStatusLoaded(RemoteAccess)
  // The Remote access Connect button; the flow blocks on a browser
  // round-trip, so the section shows an in-progress state until a
  // finished/failed message settles it.
  RemoteConnectClicked
  RemoteConnectFinished(RemoteAccess)
  RemoteConnectFailed(String)
  // The Cancel beside a waiting Connect: fires `auth.cancel`; the pending
  // connect settles the section through its own failure reply.
  RemoteCancelClicked
  // The Remote access Disconnect button and its failure (success arrives
  // as `RemoteStatusLoaded` via the op's reply).
  RemoteDisconnectClicked
  RemoteDisconnectFailed(String)
  // A `check_update` reply (or its failure, folded into `Unreachable`).
  // `explicit` says a user asked, which is what decides how loudly each
  // outcome shows.
  UpdateCheckFinished(result~ : UpdateCheck, explicit~ : Bool)
  // The accent Update button (sidebar or Settings row): confirm first when
  // a conversation is running, otherwise start the download.
  UpdateClicked
  // The interrupt-confirmation modal's two exits.
  ConfirmUpdateRestart
  CancelUpdateRestart
  // `download_update` finished: the bundle is staged and verified.
  UpdateDownloaded
  // The download or the swap failed; back to Available with a toast.
  UpdateFailed(message~ : String)
  // The host swapped the bundle; close the window so `main` can relaunch.
  UpdateApplied
  OpenSetup
  ToggleSidebar
  // The window was resized; `width` decides the narrow (phone) layout.
  ViewportResized(width~ : Int)
  // The sidebar's "Chats" heading was clicked — fold or unfold the section.
  ToggleChatsSection
  // The sidebar's "Workspaces" heading was clicked — fold or unfold the section.
  ToggleWorkspacesSection
  SaveApiKey
  OpenSkills
  SkillsQueryChanged(String)
  SkillsCatalogLoaded(Array[@transcript.MarketSkillItem])
  SkillsCatalogFailed(String)
  // A failure outside install/uninstall (the installed-list refresh).
  SkillsNotice(String)
  InstallSkill(@transcript.MarketSkillItem)
  // Uninstall by library entry id; only registry installs get the button.
  UninstallSkill(String)
  // An install/uninstall settled: `key` is the busy entry to release, and a
  // non-empty `error` becomes the panel's notice (success refreshes the
  // installed list instead).
  SkillActionDone(channel~ : @interop.ChannelId, key~ : String, error~ : String)
  Send
  Stop
  NewChat
  // The channel is captured when rotation is requested, so a focus move can
  // fence the delayed id instead of activating it on the newly focused host.
  SessionRotated(@interop.ConversationKey)
  // Open a conversation on one device's channel; clicking another
  // device's row is also the console's focus switch.
  OpenSession(@interop.ChannelId, String)
  // The user clicked the system notification posted through Proton's
  // notification extension: jump to the conversation that owned that run.
  // The native extension brings the window forward before emitting the click.
  NotificationClicked(run_id~ : String)
  // A host-side action with no conversation of its own (opening a file in
  // the system app, opening an external URL, launching an app) failed: pops
  // an error toast.
  HostActionFailed(String)
  // A safe external anchor was clicked in the Proton page. The document-level
  // capture listener emits this for both Rabbita transcript links and the
  // editor hover's foreign DOM; browser pages keep native new-tab behavior.
  ExternalLinkClicked(String)
  // Open the in-app folder picker against one device's host (browsing
  // starts at that host's home directory); on the console this also
  // focuses the device the picker will register the workspace on.
  PickWorkspace(@interop.ChannelId)
  // Browse into a directory: a subdirectory row, the parent, or the typed
  // path field on Enter.
  WorkspacePickerNavigate(String)
  // One directory's listing came back from the host; `generation` names
  // the browse request it answers, so a stale reply is dropped.
  WorkspacePickerLoaded(
    channel~ : @interop.ChannelId,
    path~ : String,
    entries~ : Array[String],
    generation~ : Int
  )
  // A navigation failed; the message shows in the picker and the previous
  // listing stays usable.
  WorkspacePickerFailed(
    channel~ : @interop.ChannelId,
    message~ : String,
    generation~ : Int
  )
  // The picker's path field changed.
  WorkspacePickerInput(String)
  // Register the picker's current directory and close it.
  WorkspacePickerConfirm
  WorkspacePickerClose
  // Detach a workspace from one device: only the registry entry goes
  // away — the directory and the sessions inside it stay, so re-adding
  // restores them.
  RemoveWorkspace(@interop.ChannelId, String)
  // Start a fresh conversation in a device's workspace ("" = the default
  // store); on the console this also focuses that device.
  NewChatIn(@interop.ChannelId, String)
  // Archive a conversation on its device: the host moves its durable
  // record into the store's `archived` twin and the sidebar moves the row
  // under the Archived group.
  ArchiveSession(@interop.ChannelId, String)
  // Restore an archived conversation into its device's live list.
  UnarchiveSession(@interop.ChannelId, String)
  // The transcript's at-bottom state changed (the user scrolled away from,
  // or back to, the tail). Reported by the DOM scroll watcher.
  TranscriptPinned(Bool)
  // The floating "jump to latest" button: scroll the transcript back to its
  // tail and re-pin auto-follow.
  JumpToLatest
  // The host's dark-mode preference changed (the user switched the OS theme).
  // Reported by the `matchMedia` watcher.
  ColorSchemeChanged(Bool)
  // A file path in the transcript was clicked: open it in the system's
  // default app. The host resolves the path inside the active conversation's
  // workspace.
  OpenFile(String)
  // Open or close the topbar app launcher; opening it fetches the installed-app
  // list the first time.
  ToggleLauncher
  LauncherLoaded(Array[@transcript.LauncherAppItem])
  LauncherFailed(String)
  // Launch one detected app (by its id) on the active conversation's workspace.
  LaunchApp(String)
  // The editor side-panel's own messages (tree, viewer, diagnostics,
  // comments), routed to the `fileeditor` package's update. The one
  // exception is `EditorCommentAdded`, which this update intercepts: the
  // comment becomes a chip on the composer draft, which only the app model
  // knows about.
  FileEditor(@fileeditor.Msg)
  // A message produced by one device channel's connection — its lifecycle,
  // its notification stream, and every reply fenced by its connection
  // generation — tagged with the channel it came from.
  FromDevice(@interop.ChannelId, DeviceMsg)
}

///|
/// Everything one device channel's connection can tell the app: its
/// lifecycle, its notification stream, and every reply fenced by its
/// connection generation. Root `Msg` carries these as
/// `FromDevice(channel, ...)`; messages that back page-global or
/// focused-scoped state stay on `Msg` itself.
priv enum DeviceMsg {
  BridgeReady
  BridgeUnavailable(String)
  // The channel's WebSocket closed (or failed to open). The handler counts
  // the loss and schedules `ReconnectDue`, making the model's device list
  // the single authority over which reconnect loops keep running.
  ChannelDown
  // A scheduled reconnect attempt came due. Dropped harmlessly when the
  // device was removed in the meantime — no `DeviceState`, no handler.
  ReconnectDue
  // A file-panel-scoped host push (`fs.changed`, `lsp.diagnostics`),
  // stamped with its channel: the panel serves the focused conversation,
  // so a background device's filesystem noise is dropped at the arm.
  FilePanel(@fileeditor.Msg)
  // The host's `host.meta` reply: whether the host itself can run the engine
  // inside WSL (a Windows host). The page's own platform says nothing — a
  // phone browser may drive a Windows host and a Windows browser a Mac one.
  HostMetaLoaded(wsl~ : Bool)
  // The host's settings, from a `settings.get` reply or a peer client's
  // edit broadcast as `settings.changed`. Applied only while no local write
  // is in flight — see `Model::settings_saves`.
  HostSettingsLoaded(HostSettings, connection_generation~ : Int?)
  // A `settings.set` this client sent came back with the post-write state.
  HostSettingsApplied(
    HostSettings,
    connection_generation~ : Int,
    cleans_legacy~ : Bool
  )
  // A `settings.set` this client sent failed; the message pops as a toast.
  HostSettingsSaveFailed(
    String,
    connection_generation~ : Int,
    cleans_legacy~ : Bool
  )
  // A `skills.installed` reply is channel-scoped just like the invalidation
  // that prompted it. Only the currently focused host may replace the
  // page's library mirror.
  InstalledSkillsLoaded(Array[@transcript.InstalledSkillItem])
  InstalledSkillsFailed(String)
  // Another client changed this host's library; the focused client re-reads
  // it so the Skills page and `$` completion share the new contents.
  SkillsChanged
  // The steer RPC failed before its outcome was known. The host may already
  // have accepted it, so its notice/ledger entry stays provisional.
  SteerUndelivered(
    session~ : String,
    submission_id~ : String,
    text~ : String,
    run_id~ : String
  )
  // The host definitively returned `steered:false`; no canonical User can
  // follow, so both pending UI and its ledger entry retire immediately.
  SteerRejected(
    session~ : String,
    submission_id~ : String,
    text~ : String,
    run_id~ : String
  )
  SessionsLoaded(
    Array[@transcript.SessionListItem],
    connection_generation~ : Int,
    request_generation~ : Int
  )
  SessionsFailed(String)
  // The host's identity-bearing `session.changed` broadcast. Archive changes
  // invalidate that exact live target immediately; both sidebar lists are
  // then re-read for their durable contents.
  SessionsChanged(change~ : String, session~ : String, fresh_session~ : String?)
  SessionLoaded(
    session~ : String,
    items~ : Array[@transcript.TranscriptItem],
    watermark~ : Int,
    event_boundaries~ : Array[(Int, Bool, Int)],
    generation~ : Int
  )
  // A foreground stored-session read failed. Generation guards stale replies;
  // bounded retries keep the selection pending before final failure is shown.
  SessionLoadFailed(session~ : String, message~ : String, generation~ : Int)
  // A background re-read of a conversation's durable record (a commit-gap
  // resync, or a reload for a foreign run): same data as `SessionLoaded`,
  // but it never activates the conversation or steals the screen.
  SessionRefreshed(
    session~ : String,
    items~ : Array[@transcript.TranscriptItem],
    watermark~ : Int,
    event_boundaries~ : Array[(Int, Bool, Int)],
    generation~ : Int
  )
  // A background re-read failed. The generation identifies the exact read,
  // so an old failure cannot stop a newer one.
  SessionRefreshFailed(session~ : String, generation~ : Int)
  // The host's `session.event` broadcast: one durably committed store event.
  // Together with `session.load` snapshots these are the transcript's only
  // durable sources; the live `agent.event` stream is lifecycle/stream state.
  SessionCommitted(
    session~ : String,
    sequence~ : Int,
    kind~ : String,
    payload~ : Map[String, Json]
  )
  // The registered workspaces — the reply to `workspace.list`. Both
  // generations are required: reconnect rejects a dead socket, while request
  // generation rejects an older reply from the current connection.
  WorkspacesLoaded(
    Array[String],
    connection_generation~ : Int,
    request_generation~ : Int
  )
  // The host's canonical post-commit registry broadcast. Every client adopts
  // the same list in durable write order and invalidates older list replies.
  WorkspacesChanged(Array[String])
  WorkspaceFailed(String)
  // The archived conversations — the reply to `archived_sessions` and to a
  // successful `archive_session`/`unarchive_session` alike.
  ArchivedLoaded(
    Array[@transcript.SessionListItem],
    connection_generation~ : Int,
    request_generation~ : Int,
    fresh_session~ : String
  )
  ArchiveFailed(String)
  // A `workspace_branch` reply: the git branch of `session`'s workspace —
  // `Some("")` when it is not a repository, `None` when the probe failed or
  // answered unintelligibly.
  BranchLoaded(session~ : String, branch~ : String?)
  // The host accepted a prompt: `session` routes the event to its
  // conversation, and everything after a `started` routes by `run_id`.
  // `task` is the prompt text — a client that did not send it (another
  // window, a mid-run join) has no other live source for the prompt bubble.
  Started(
    run_id~ : String,
    session~ : String,
    model~ : String,
    max_steps~ : Int,
    cwd~ : @pathx.Absolute?,
    session_root~ : @pathx.Absolute?,
    task~ : String?,
    submission_id~ : String?
  )
  // One complete `agent.runs` reply. Replayed starts and the negative-set
  // frontier must be accepted or rejected together at one connection
  // generation; dispatching its rows separately would let a stale reply
  // resurrect a run after a later BridgeReady already resynced it away.
  RunsLoaded(
    runs~ : Array[RecoveredRun],
    settled~ : Array[RecoveredSettlement],
    live~ : Array[String],
    frontier~ : Array[RunSnapshotFrontier],
    connection_generation~ : Int
  )
  // The complete in-flight run set, from an `agent.runs` resync. Any
  // conversation still showing an open run this set lacks ended while the
  // client was away — its terminal event is gone for good (reconnect =
  // resync; transients are not replayed), so this is what closes it.
  RunsSettled(live~ : Array[String], frontier~ : Array[RunSnapshotFrontier])
  // A stream event from an engine. The run id is `None` for events emitted
  // before any run of the engine process's lifetime. `session` is the
  // conversation the host stamped on it (`None` when the payload carries no
  // stamp): idle events (the compaction lifecycle, background notices) route
  // by it, because a conversation compacted before its first prompt of this
  // app-lifetime has no run id to match.
  Engine(String?, @transcript.EngineEvent, session~ : String?)
  // The exact local start request returned its run result. `accepted` is the
  // prompt's ownership receipt and can recover a Started notification lost on
  // the same connection; any other status leaves delivery unconfirmed.
  StartResponded(
    session~ : String,
    submission_id~ : String,
    run_id~ : String,
    status~ : String,
    exit_code~ : Int
  )
  // The response path failed before host acceptance was knowable. Keep an
  // exact-id unconfirmed entry; canonical transcript text cannot settle it.
  StartUndelivered(
    session~ : String,
    submission_id~ : String,
    message~ : String
  )
  // The host definitively refused this exact request. Restore its draft and
  // retire the ledger entry immediately.
  StartRejected(session~ : String, submission_id~ : String, message~ : String)
  // A host error without a run (`run_id` is `None` — a pre-run failure)
  // belongs to whatever conversation the user is looking at; `diagnostics`
  // is stderr worth appending, when the host captured any. With a run,
  // `exit_code` distinguishes a local process-exit diagnostic from semantic
  // agent failures that already have a durable terminal commit.
  Error(
    run_id~ : String?,
    message~ : String,
    diagnostics~ : String?,
    exit_code~ : Int?
  )
  // The `compact` bridge request itself was rejected (no engine, host error):
  // nothing will report compaction events, so the conversation's queued /
  // in-flight compaction notice must be cleared here, not by the stream.
  CompactRejected(session~ : String, message~ : String)
  // `answer` accompanies normal success and context yield (where it is
  // continuation guidance); other terminal statuses carry none.
  Finished(
    run_id~ : String,
    status~ : String,
    answer~ : String?,
    durable_sequence~ : Int?
  )
  // A failed command's process reached EOF after lifecycle was already
  // settled. This is only the exact durable boundary, never a second finish.
  DurableBoundary(run_id~ : String, session~ : String, sequence~ : Int)
}

///|
/// A workspace registry token ("" = the default store) as a typed root. The
/// tokens come from the host's registry and store replies, so a non-empty one
/// is known-absolute — this is the one place that provenance is collapsed
/// into the type.
fn workspace_root(token : String) -> @pathx.Absolute? {
  if token.is_empty() {
    None
  } else {
    Some(Absolute(token))
  }
}

///|
/// A conversation's workspace back in registry-token form ("" = the default
/// store), for sidebar grouping and store-addressed ops.
fn workspace_token(root : @pathx.Absolute?) -> String {
  if root is Some(root) {
    root.0
  } else {
    ""
  }
}

///|
fn empty_conversation(
  channel : @interop.ChannelId,
  session_id : String,
  workspace? : String = "",
) -> Conversation {
  {
    device: channel,
    session_id,
    workspace: workspace_root(workspace),
    task: "",
    mentions: [],
    run: NoRun(ended=None),
    last_run_id: None,
    last_terminal_sequence: 0,
    run_durable_floor: None,
    run_floor_generation: None,
    compaction: NotCompacting,
    unseen_finish: false,
    usage_tokens: 0,
    cwd: None,
    branch: None,
    watcher_status: "",
    streaming_response: "",
    input_ledger: [],
    messages: [],
    watermark: 0,
    sync: Synced,
    overlay: [],
  }
}

///|
fn initial_model() -> Model {
  // Read once here (main runs before the first render); afterwards the
  // resize subscription keeps the flag current through `ViewportResized`.
  // No window (a headless test runtime) reads as the wide layout.
  let narrow = match @interop.viewport_width() {
    Some(width) => width <= NarrowBreakpoint
    None => false
  }
  // A deep link may preselect the project (`?workspace=`) and, on the
  // browser console, the device (`?device=`, minted by the relay's redirect
  // off the retired `/d/<id>/` routes); the first conversation lands there.
  let preselect_workspace = @interop.page_query_param("workspace")
  {
    // The desktop window's one channel; a browser page starts empty and
    // fills `devices` from the fetched roster (`apply_roster`).
    devices: match @interop.page_channel() {
      Some(channel) =>
        [
          {
            ..empty_device_state(channel),
            active_workspace: preselect_workspace.unwrap_or(""),
          },
        ]
      None => []
    },
    focused: @interop.page_channel().unwrap_or(@interop.ChannelId::Local),
    selected_model: DefaultModel,
    max_steps: DefaultMaxSteps,
    deepseek_key_saved: false,
    custom_key_saved: false,
    setup_api_key: "",
    api_provider: Openseek,
    custom_api_url: "",
    settings_saves: 0,
    host_settings_revision: -1,
    deferred_host_settings: None,
    legacy_cleanup_pending: false,
    host_wsl: false,
    is_desktop: @interop.using_proton_bridge(),
    // Every browser page is the console: it signs in against the relay and
    // fetches the device roster before any channel opens.
    console: if @interop.using_proton_bridge() {
      None
    } else {
      Some(
        empty_console_state(
          @interop.page_query_param("device"),
          preselect_workspace,
        ),
      )
    },
    wsl_enabled: false,
    wsl_distro: "",
    wsl_engine: "",
    dark_mode: host_prefers_dark(),
    narrow,
    sidebar_open: !narrow,
    chats_collapsed: false,
    workspaces_collapsed: false,
    active_session: "",
    loading_conversation: None,
    transcript_request_generation: 0,
    submission_namespace: generated_session_id() + "-submission",
    submission_sequence: 0,
    conversations: [],
    workspace_picker: None,
    transcript_pinned: true,
    screen: Chat,
    skills_catalog: CatalogIdle,
    installed_skills: [],
    skills_query: "",
    skills_busy: [],
    skills_notice: "",
    completion: None,
    symbol_cache: empty_symbol_cache(),
    launcher: { open: false, apps: AppsNotFetched },
    file_panel: @fileeditor.State::empty(),
    notifications: [],
    notification_seq: 0,
    notification_corner: BottomRight,
    tree_layout: RightSidebar,
    update_ux: UpdateUnknown,
    remote_access: None,
    remote_connecting: false,
    remote_error: None,
  }
}

///|
/// The state of one connected channel; `None` for a channel this page does
/// not hold — one the roster retired, or any channel before a browser
/// console's first roster arrives.
fn Model::device_state(
  self : Model,
  channel : @interop.ChannelId,
) -> DeviceState? {
  for dev in self.devices {
    if dev.channel == channel {
      return Some(dev)
    }
  }
  None
}

///|
/// The focused channel's state — what the sidebar, Settings, and the
/// composer act on.
fn Model::focused_device(self : Model) -> DeviceState? {
  self.device_state(self.focused)
}

///|
/// Replace the entry sharing `dev`'s channel, copy-on-write — prior model
/// snapshots keep their own devices array. A channel this page does not
/// hold is not adopted: device state only ever exists for channels the
/// page connected.
fn Model::replace_device(self : Model, dev : DeviceState) -> Model {
  let devices = self.devices.copy()
  for index, existing in devices {
    if existing.channel == dev.channel {
      devices[index] = dev
      return { ..self, devices, }
    }
  }
  { ..self, devices, }
}

///|
/// The focused channel's connection generation — the fence root-scoped
/// fetches (host settings, session snapshots) stamp on their requests. 0
/// when the page holds no devices; no reply ever arrives to check it there.
fn Model::focused_connection_generation(self : Model) -> Int {
  match self.focused_device() {
    Some(dev) => dev.connection_generation
    None => 0
  }
}

///|
/// Move the focused channel's "New chat" placement.
fn Model::with_active_workspace(self : Model, workspace : String) -> Model {
  guard self.focused_device() is Some(dev) else { return self }
  self.replace_device({ ..dev, active_workspace: workspace })
}

///|
/// The focused device's roster name — the console banner's subject. The
/// desktop window (no roster) is always its own local host.
fn Model::focused_device_name(self : Model) -> String {
  if self.console is Some(console) && self.focused is Remote(id) {
    for meta in console.roster {
      if meta.id == id {
        return meta.name
      }
    }
  }
  "OpenSeek"
}

///|
/// The focused channel's bridge state, `Connecting` when the page holds no
/// devices — keeps the view total before a browser console's roster lands.
fn Model::bridge_state(self : Model) -> BridgeState {
  match self.focused_device() {
    Some(dev) => dev.bridge
    None => Connecting
  }
}

///|
/// Whether a catalog entry (identified by its source label) is already in
/// the local library — at that exact version; an older install keeps the
/// Install button alive as the upgrade path.
fn Model::skill_installed(self : Model, source : String) -> Bool {
  for skill in self.installed_skills {
    if skill.source == source {
      return true
    }
  }
  false
}

///|
/// Fold one host settings payload into the mirror. The default provider
/// needs no setup, so the Settings page only takes over when the settings
/// are incomplete (official endpoint without a key, custom endpoint without
/// a URL); it never navigates away on its own.
fn Model::apply_host_settings(self : Model, settings : HostSettings) -> Model {
  let next = {
    ..self,
    host_settings_revision: settings.revision,
    deferred_host_settings: None,
    api_provider: ApiProvider::parse(settings.provider),
    custom_api_url: settings.custom_api_url,
    deepseek_key_saved: settings.has_deepseek_key,
    custom_key_saved: settings.has_custom_key,
    wsl_enabled: settings.wsl_enabled,
    wsl_distro: settings.wsl_distro,
    wsl_engine: settings.wsl_engine,
  }
  { ..next, screen: if next.api_ready() { next.screen } else { Settings } }
}

///|
/// Retain the highest host revision observed while one or more optimistic
/// writes are outstanding. The body is applied only when the last write
/// settles, preventing both stale rollback and mid-edit UI clobbering.
fn Model::defer_host_settings(self : Model, settings : HostSettings) -> Model {
  if settings.revision < self.host_settings_revision {
    return self
  }
  let deferred = match self.deferred_host_settings {
    Some(current) if current.revision > settings.revision => current
    _ => settings
  }
  { ..self, deferred_host_settings: Some(deferred) }
}

///|
/// Apply the newest deferred status once optimistic writes no longer protect
/// the form. A lower revision is discarded; equal is deliberately accepted
/// so a failed optimistic edit can be restored by an authoritative `get`.
fn Model::flush_host_settings(self : Model) -> Model {
  match self.deferred_host_settings {
    Some(settings) if settings.revision >= self.host_settings_revision =>
      self.apply_host_settings(settings)
    _ => { ..self, deferred_host_settings: None }
  }
}

///|
/// Whether the configured endpoint is usable as it stands: the default
/// OpenSeek proxy always is, the official endpoint needs a key stored on
/// the host, and a custom endpoint needs at least a URL. The credentials
/// themselves live on the host; a start carries none.
fn Model::api_ready(self : Model) -> Bool {
  match self.api_provider {
    Openseek | OpenseekStaging => true
    Deepseek => self.deepseek_key_saved
    Custom => !self.custom_api_url.trim().is_empty()
  }
}

///|
/// The status implied by the settings alone: whether the configured endpoint
/// is ready to accept a prompt, and what is missing when it is not.
fn Model::settings_status(self : Model) -> Status {
  if self.api_ready() {
    Ready
  } else if self.api_provider is Deepseek {
    ApiKeyRequired
  } else {
    SetupRequired
  }
}

///|
/// The status the top bar shows: bridge problems first, then the active
/// conversation's own run state, and — only when that conversation is idle —
/// the settings-derived readiness. Purely derived, so update handlers never
/// have to keep a stored status in sync with settings changes.
fn Model::display_status(self : Model) -> Status {
  match self.bridge_state() {
    Connecting => WaitingBridge
    BridgeLost(message) => Unavailable(message)
    Connected =>
      match self.active().run {
        NoRun(ended=None) => self.settings_status()
        NoRun(ended=Some(RunFailed)) => Failed
        NoRun(ended=Some(RunErrored)) => Errored
        NoRun(ended=Some(RunFinished(outcome))) => Finished(outcome)
        Starting(..) => Starting
        Open(stage=Opened, ..) => Running
        Open(stage=AtStep(step), ..) => Step(step)
        Open(stage=Cancelling, ..) => Cancelling
      }
  }
}

///|
fn Model::find_conversation(
  self : Model,
  channel : @interop.ChannelId,
  session_id : String,
) -> Conversation? {
  for conv in self.conversations {
    if conv.device == channel && conv.session_id == session_id {
      return Some(conv)
    }
  }
  None
}

///|
/// Capture the exact lifecycle identity of every session currently known to
/// this page. Absence is meaningful too: a snapshot may introduce an unknown
/// session only if no live notification materialized it before the reply.
fn Model::run_snapshot_frontier(
  self : Model,
  channel : @interop.ChannelId,
) -> Array[RunSnapshotFrontier] {
  self.conversations
  .filter(conv => conv.device == channel)
  .map(conv => {
    let state = match conv.run {
      NoRun(..) => SnapshotIdle(last_run_id=conv.last_run_id)
      Starting(submission_id~) => SnapshotStarting(submission_id~)
      Open(run_id~, ..) => SnapshotOpen(run_id~)
    }
    let initial_ids : Array[String] = []
    for input in conv.input_ledger {
      if input.kind is InitialPrompt && input.run_id is None {
        initial_ids.push(input.submission_id)
      }
    }
    let steer_ids : Array[String] = []
    let steer_owner = match state {
      SnapshotOpen(run_id~) => Some(run_id)
      SnapshotIdle(last_run_id=Some(run_id)) => Some(run_id)
      _ => None
    }
    if steer_owner is Some(run_id) {
      for input in conv.input_ledger {
        if input.kind is SteerInput &&
          input.run_id is Some(owner) &&
          owner == run_id {
          steer_ids.push(input.submission_id)
        }
      }
    }
    { session: conv.session_id, state, initial_ids, steer_ids }
  })
}

///|
/// Whether `session` still has exactly the lifecycle state captured when a
/// runs snapshot began. This is the acceptance gate for each positive row.
/// If the session was absent from the frontier, it must still be absent now.
fn Model::matches_run_snapshot_frontier(
  self : Model,
  channel : @interop.ChannelId,
  frontier : Array[RunSnapshotFrontier],
  session : String,
) -> Bool {
  for captured in frontier {
    if captured.session == session {
      guard self.find_conversation(channel, session) is Some(conv) else {
        return false
      }
      return match captured.state {
        SnapshotIdle(last_run_id~) =>
          conv.run is NoRun(..) && conv.last_run_id == last_run_id
        SnapshotStarting(submission_id~) =>
          conv.run is Starting(submission_id=current) &&
          current == submission_id
        SnapshotOpen(run_id~) =>
          conv.run is Open(run_id=current, ..) && current == run_id
      }
    }
  }
  self.find_conversation(channel, session) is None
}

///|
/// Match a replayed completion to the exact lifecycle owner captured when
/// `agent.runs` began. Starting has no run id yet, so it uses the client's
/// submission id; Open/Idle use the host run id. The session is required in
/// every case, and current state must still equal the captured cut.
fn Model::matched_settlement_frontier(
  self : Model,
  channel : @interop.ChannelId,
  frontier : Array[RunSnapshotFrontier],
  settlement : RecoveredSettlement,
) -> SettlementFrontierMatch? {
  guard self.find_conversation(channel, settlement.session) is Some(conv) else {
    return None
  }
  for captured in frontier {
    if captured.session == settlement.session {
      return match captured.state {
        SnapshotStarting(submission_id~) if conv.run
          is Starting(submission_id=current) &&
          current == submission_id &&
          settlement.submission_id is Some(recovered) &&
          recovered == submission_id =>
          Some(SettlementBySubmission(submission_id))
        SnapshotOpen(run_id~) if conv.run is Open(run_id=current, ..) &&
          current == run_id &&
          settlement.run_id == run_id => Some(SettlementByRun)
        SnapshotIdle(last_run_id=Some(run_id)) if conv.run is NoRun(..) &&
          conv.last_run_id is Some(current) &&
          current == run_id &&
          settlement.run_id == run_id => Some(SettlementByRun)
        _ =>
          if conv.run is NoRun(..) &&
            settlement.submission_id is Some(submission_id) &&
            captured.initial_ids.contains(submission_id) &&
            conv.input_ledger
            .iter()
            .any(input => {
              input.kind is InitialPrompt &&
              input.submission_id == submission_id &&
              input.run_id is None
            }) {
            Some(SettlementBySubmission(submission_id))
          } else {
            None
          }
      }
    }
  }
  None
}

///|
/// The workspace a session belongs to on `channel`: the sidebar list's
/// grouping when the store knows the session, the live conversation's own
/// placement otherwise (a fresh chat that has not reached the store yet).
/// "" = the default store.
fn Model::session_workspace(
  self : Model,
  channel : @interop.ChannelId,
  session_id : String,
) -> String {
  let sessions = match self.device_state(channel) {
    Some(dev) => dev.sessions
    None => []
  }
  for item in sessions {
    if item.id == session_id {
      return item.workspace
    }
  }
  match self.find_conversation(channel, session_id) {
    Some(conv) => workspace_token(conv.workspace)
    None => ""
  }
}

///|
/// Resolve a host-reported durable session root back to a registered
/// workspace. Workspace conversations live at `<workspace>/.openseek`;
/// scratch conversations use the unrelated global root and therefore do not
/// match anything here. The lexical helper normalizes Windows separators.
fn DeviceState::workspace_for_session_root(
  self : DeviceState,
  session_root : @pathx.Absolute?,
) -> String? {
  guard session_root is Some(session_root) else { return None }
  for workspace in self.workspaces {
    if @pathx.relative_to(session_root.0, root=workspace) is Some(".openseek") {
      return Some(workspace)
    }
  }
  None
}

///|
/// The newest archive disposition this connection observed for `session`,
/// if any. `true` means archived and `false` means live.
fn DeviceState::archive_override(self : DeviceState, session : String) -> Bool? {
  for fact in self.archive_overrides {
    if fact.session == session {
      return Some(fact.archived)
    }
  }
  None
}

///|
/// One channel's archive disposition for `session` — the Model-level view
/// of `DeviceState::archive_override`.
fn Model::archive_override(
  self : Model,
  channel : @interop.ChannelId,
  session : String,
) -> Bool? {
  guard self.device_state(channel) is Some(dev) else { return None }
  dev.archive_override(session)
}

///|
/// Record one archive notification as the sole current override for its
/// session on `channel`. This copy-on-write replacement is what lets every
/// later list or commit handler consult the same monotonic fact.
fn Model::with_archive_override(
  self : Model,
  channel : @interop.ChannelId,
  session : String,
  archived : Bool,
) -> Model {
  guard self.device_state(channel) is Some(dev) else { return self }
  let overrides = dev.archive_overrides.filter(item => item.session != session)
  overrides.push({ session, archived })
  self.replace_device({ ..dev, archive_overrides: overrides })
}

///|
/// Whether re-reading this conversation can address a durable record. Local
/// overlays and a failed pre-persistence start do not prove one exists; using
/// them as a reload gate would turn every reconnect/reselect into three noisy
/// `session.load` failures for an unsaved chat.
fn Model::can_reload_transcript(self : Model, conv : Conversation) -> Bool {
  if conv.watermark > 0 ||
    !conv.messages.is_empty() ||
    conv.sync is ReloadFailed(..) ||
    conv.has_recovering_initial() ||
    conv.overlay.iter().any(notice => notice.anchor is SnapshotCut(..)) {
    return true
  }
  match self.device_state(conv.device) {
    Some(dev) => dev.sessions.iter().any(item => item.id == conv.session_id)
    None => false
  }
}

///|
/// The conversation on screen. Until the startup session rotation lands the
/// model has no conversations yet; an empty placeholder keeps the view (and
/// every handler reading the active conversation) total.
fn Model::active(self : Model) -> Conversation {
  if self.find_conversation(self.focused, self.active_session) is Some(conv) {
    conv
  } else {
    empty_conversation(self.focused, self.active_session)
  }
}

///|
/// Whether the conversation on screen is a fresh "New chat" — nothing sent
/// yet and no stored record. While this holds, the conversation owns a
/// "New chat" sidebar row in its workspace's group, taking a real title at
/// the first send.
fn Model::composing_new_chat(self : Model) -> Bool {
  let conv = self.active()
  if conv.has_begun() {
    return false
  }
  guard self.focused_device() is Some(dev) else { return true }
  for item in dev.sessions {
    if item.id == conv.session_id {
      return false
    }
  }
  true
}

///|
/// Replace (or add) the entry sharing `conv`'s session id, copy-on-write —
/// prior model snapshots keep their own conversations array.
fn Model::replace_conversation(self : Model, conv : Conversation) -> Model {
  let conversations = self.conversations.copy()
  for index, existing in conversations {
    if existing.device == conv.device && existing.session_id == conv.session_id {
      conversations[index] = conv
      return { ..self, conversations, }
    }
  }
  conversations.push(conv)
  { ..self, conversations, }
}

///|
/// The conversation that owns run `run_id`. Engine events route by run id,
/// so a backgrounded conversation keeps receiving its own stream.
fn Model::conversation_by_run(
  self : Model,
  channel : @interop.ChannelId,
  run_id : String,
) -> Conversation? {
  for conv in self.conversations.filter(conv => conv.device == channel) {
    if conv.run is Open(run_id=active, ..) && active == run_id {
      return Some(conv)
    }
  }
  None
}

///|
/// The conversation that most recently owned run `run_id`, matched even after
/// the run finished. Used to route compaction events, which the engine stamps
/// with its last run id while sitting idle between turns.
fn Model::conversation_by_last_run(
  self : Model,
  channel : @interop.ChannelId,
  run_id : String,
) -> Conversation? {
  for conv in self.conversations.filter(conv => conv.device == channel) {
    if conv.last_run_id is Some(last) && last == run_id {
      return Some(conv)
    }
  }
  None
}

///|
/// The conversation holding an exact id-bearing steer receipt. A receipt may
/// trail its run's Finished event and even the next run's Started event, so
/// current/last run ownership alone is not enough to route it.
fn Model::conversation_by_pending_steer(
  self : Model,
  channel : @interop.ChannelId,
  submission_id : String,
  run_id : String,
) -> Conversation? {
  for conv in self.conversations.filter(conv => conv.device == channel) {
    for input in conv.input_ledger {
      if input.kind is SteerInput &&
        input.submission_id == submission_id &&
        input.run_id is Some(owner) &&
        owner == run_id {
        return Some(conv)
      }
    }
  }
  None
}

///|
/// Make `session_id` the on-screen conversation, creating its entry when it
/// has none, and drop conversations with nothing worth keeping. Exact input
/// ownership is retained even after lifecycle recovery closes a run: a late
/// id-bearing receipt or rejection may still retract a warning or restore its
/// draft. Abandoned "New chat" husks die here instead of accumulating.
fn Model::activate(
  self : Model,
  channel : @interop.ChannelId,
  session_id : String,
) -> Model {
  let conversations : Array[Conversation] = []
  let mut found = false
  for conv in self.conversations {
    if conv.device == channel && conv.session_id == session_id {
      found = true
      // Opening the conversation is what "seen" means.
      conversations.push({ ..conv, unseen_finish: false })
    } else if conv.has_begun() || !conv.draft_empty() {
      conversations.push(conv)
    }
  }
  if !found {
    conversations.push(empty_conversation(channel, session_id))
  }
  // Activating a conversation is also what moves the UI's focus to its
  // device — a no-op while the app runs a single channel.
  { ..self, focused: channel, active_session: session_id, conversations }
}

///|
/// Whether the composer draft holds nothing at all — no typed text and no
/// mention chips. This is the retention test (`Model::activate` keeps a
/// conversation whose draft still holds anything), not the send gate: that is
/// `draft_sendable`.
fn Conversation::draft_empty(self : Conversation) -> Bool {
  self.task.trim().is_empty() && self.mentions.is_empty()
}

///|
/// Whether the draft can be submitted: only typed text makes a prompt.
/// Chips alone don't send — a mention is context *for* an instruction, so
/// the instruction is required; the chips ride along in the envelope.
fn Conversation::draft_sendable(self : Conversation) -> Bool {
  !self.task.trim().is_empty()
}

///|
/// Whether the conversation has actually gotten under way — a run, durable
/// transcript, local notice, or exact submission ownership. A fresh "New
/// chat" (even with a typed draft) has not; the one on screen still owns a
/// "New chat" sidebar row, but stale husks stay out of the list.
fn Conversation::has_begun(self : Conversation) -> Bool {
  self.is_running() ||
  self.messages.length() > 0 ||
  self.overlay.length() > 0 ||
  !self.input_ledger.is_empty()
}

///|
/// A run is in flight for this conversation — starting or open. The send
/// composer, sidebar pulse, and self-update busy check all gate on this.
fn Conversation::is_running(self : Conversation) -> Bool {
  !(self.run is NoRun(..))
}

///|
fn Conversation::clear_streams(self : Conversation) -> Conversation {
  { ..self, streaming_response: "" }
}

///|
/// Append one client-local notice at the current durable chronology boundary.
fn Conversation::append_notice(
  self : Conversation,
  kind : @transcript.ItemKind,
  content : String,
  reconciliation : NoticeReconciliation,
) -> Conversation {
  let overlay = self.overlay.copy()
  overlay.push({
    kind,
    content,
    anchor: AfterMessages(self.messages.length()),
    reconciliation,
  })
  { ..self, overlay, }
}

///|
/// Choose the only safe chronology proof for a run-finish notice. A
/// terminal-backed finish waits for the post-Finished snapshot generation;
/// every other status remains anonymous until the host supplies an exact
/// durable boundary.
fn Conversation::run_tail_notice_anchor(
  self : Conversation,
  terminal_expected? : Bool = true,
  terminal_snapshot_generation? : Int,
) -> NoticeAnchor {
  if terminal_expected {
    match (self.run_durable_floor, terminal_snapshot_generation) {
      (Some(floor), Some(snapshot_generation)) =>
        PriorTerminalTail(floor~, snapshot_generation~)
      (None, Some(snapshot_generation)) => SnapshotCut(snapshot_generation~)
      _ => TerminalTail(self.run_durable_floor)
    }
  } else {
    match terminal_snapshot_generation {
      Some(snapshot_generation) => SnapshotCut(snapshot_generation~)
      None => UncertainTail
    }
  }
}

///|
/// Append a provisional submission notice that follows this run's durable
/// tail until its terminal boundary commits.
fn Conversation::append_run_tail_notice(
  self : Conversation,
  kind : @transcript.ItemKind,
  content : String,
  reconciliation : NoticeReconciliation,
  terminal_expected? : Bool = true,
  terminal_snapshot_generation? : Int,
) -> Conversation {
  let overlay = self.overlay.copy()
  let anchor = self.run_tail_notice_anchor(
    terminal_expected~,
    terminal_snapshot_generation?,
  )
  overlay.push({ kind, content, anchor, reconciliation })
  { ..self, overlay, }
}

///|
/// Append a retained local notice. Live semantic events with durable twins
/// never pass through here on their way to a commit.
fn Conversation::append_local_notice(
  self : Conversation,
  kind : @transcript.ItemKind,
  content : String,
) -> Conversation {
  self.append_notice(kind, content, Retained)
}

///|
/// A host process diagnostic is local-only, but its display position belongs
/// after that process's durable EOF frontier. Keep the run id as reconciliation
/// identity so Finished/agent.durable can place it even while transcript
/// commits are buffered behind a snapshot.
fn Conversation::append_run_diagnostic(
  self : Conversation,
  run_id : String,
  content : String,
) -> Conversation {
  self.append_run_tail_notice(
    Assistant(is_danger=true),
    content,
    RunDiagnostic(run_id),
    terminal_expected=false,
  )
}

///|
fn Model::allocate_submission_id(self : Model) -> (Model, String) {
  let sequence = self.submission_sequence + 1
  (
    { ..self, submission_sequence: sequence },
    self.submission_namespace + "-" + sequence.to_string(),
  )
}

///|
fn Conversation::enqueue_input(
  self : Conversation,
  kind : InputKind,
  submission_id : String,
  run_id : String?,
  content : String,
  draft : String,
  mentions : Array[Mention],
) -> Conversation {
  let input_ledger = self.input_ledger.copy()
  input_ledger.push({
    submission_id,
    kind,
    run_id,
    content,
    draft,
    mentions: mentions.copy(),
    state: Awaiting,
  })
  { ..self, input_ledger, }
}

///|
/// Pending steer UI is a projection of the ownership ledger, never a second
/// text queue. An unconfirmed steer leaves this panel and instead gets a
/// truthful transcript notice until an id-bearing receipt settles it.
fn Conversation::pending_steers(self : Conversation) -> Array[String] {
  let pending : Array[String] = []
  for input in self.input_ledger {
    if input.kind is SteerInput && input.state is Awaiting {
      pending.push(input.content)
    }
  }
  pending
}

///|
fn Conversation::has_recovering_initial(self : Conversation) -> Bool {
  self.input_ledger
  .iter()
  .any(input => input.kind is InitialPrompt && input.state is Unconfirmed)
}

///|
fn Conversation::has_initial_submission(
  self : Conversation,
  submission_id : String,
) -> Bool {
  self.input_ledger
  .iter()
  .any(input => {
    input.kind is InitialPrompt && input.submission_id == submission_id
  })
}

///|
fn Conversation::has_notice_for_input(self : Conversation, id : String) -> Bool {
  self.overlay
  .iter()
  .any(notice => notice.reconciliation is Submission(existing) && existing == id)
}

///|
/// Move one exact submission notice to the abnormal process exit's durable
/// frontier. An already-applied frontier has a known display boundary now;
/// an in-flight one stays sequence-addressed until its buffer/snapshot lands.
fn Conversation::anchor_submission_notice_at_durable_frontier(
  self : Conversation,
  submission_id : String,
  frontier : Int,
) -> Conversation {
  let anchor = if frontier == self.watermark {
    AfterMessages(self.messages.length())
  } else {
    DurableTail(frontier)
  }
  let overlay = self.overlay.map(notice => {
    match notice.reconciliation {
      Submission(id) if id == submission_id => { ..notice, anchor, }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// Move one exact submission warning to a causal snapshot observation cut.
/// This is used when no terminal/EOF sequence is available; it never claims
/// that an anonymous item in the snapshot belongs to the submission.
fn Conversation::anchor_submission_notice_at_snapshot_cut(
  self : Conversation,
  submission_id : String,
  snapshot_generation : Int,
) -> Conversation {
  let overlay = self.overlay.map(notice => {
    match (notice.anchor, notice.reconciliation) {
      (AfterMessages(_), Submission(id)) | (UncertainTail, Submission(id)) if id ==
        submission_id => { ..notice, anchor: SnapshotCut(snapshot_generation~) }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// A failed command may emit lifecycle Finished before its process can be
/// reaped. When EOF later supplies the final sequence, move the already-
/// unconfirmed steer notices for that exact run onto the proven boundary.
fn Conversation::anchor_unconfirmed_steers_at_durable_frontier(
  self : Conversation,
  run_id : String,
  frontier : Int,
) -> Conversation {
  let mut next = self
  for input in self.input_ledger {
    if input.kind is SteerInput &&
      input.state is Unconfirmed &&
      input.run_id is Some(owner) &&
      owner == run_id {
      next = next.anchor_submission_notice_at_durable_frontier(
        input.submission_id,
        frontier,
      )
    }
  }
  next
}

///|
/// Whether an exact input owned by `run_id` is waiting on a causal snapshot
/// cut. Runs resync uses this cross-reference instead of treating every local
/// notice as belonging to the lifecycle row it just settled.
fn Conversation::has_submission_at_snapshot_cut_for_run(
  self : Conversation,
  run_id : String,
) -> Bool {
  for input in self.input_ledger {
    if input.run_id is Some(owner) && owner == run_id {
      for notice in self.overlay {
        if notice.anchor is SnapshotCut(..) &&
          notice.reconciliation is Submission(id) &&
          id == input.submission_id {
          return true
        }
      }
    }
  }
  false
}

///|
/// Place a retained process diagnostic at the exact EOF frontier supplied by
/// Finished/agent.durable. Unlike submission notices, it has no ledger entry
/// and is never retracted.
fn Conversation::anchor_run_diagnostics_at_durable_frontier(
  self : Conversation,
  run_id : String,
  frontier : Int,
) -> Conversation {
  let anchor = if frontier == self.watermark {
    AfterMessages(self.messages.length())
  } else {
    DurableTail(frontier)
  }
  let overlay = self.overlay.map(notice => {
    match notice.reconciliation {
      RunDiagnostic(owner) if owner == run_id => { ..notice, anchor, }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// When the exact EOF sequence trails Finished, arm a process diagnostic for
/// the same causal snapshot rule as other run-tail notices. Duplicate
/// lifecycle messages cannot rewrite an already exact/frozen placement.
fn Conversation::anchor_run_diagnostics_at_finish(
  self : Conversation,
  run_id : String,
  terminal_expected : Bool,
  terminal_snapshot_generation? : Int,
) -> Conversation {
  let anchor = self.run_tail_notice_anchor(
    terminal_expected~,
    terminal_snapshot_generation?,
  )
  let overlay = self.overlay.map(notice => {
    let replace = notice.anchor is UncertainTail ||
      (terminal_expected && notice.anchor is SnapshotCut(..))
    if replace &&
      notice.reconciliation is RunDiagnostic(owner) &&
      owner == run_id {
      { ..notice, anchor, }
    } else {
      notice
    }
  })
  { ..self, overlay, }
}

///|
/// `agent.runs` may close a run and mark its steers Unconfirmed before that
/// run's exact Finished notification arrives. Reclassify those existing
/// uncertain notices by exact owner id so the later lifecycle truth can
/// upgrade a normal finish to its post-Finished snapshot proof without
/// touching another run's ledger entries. An abnormal duplicate cannot
/// downgrade an already-armed snapshot cut; every other anchor is already
/// stronger or in flight and remains idempotent across duplicate Finished.
fn Conversation::anchor_unconfirmed_steers_at_run_finish(
  self : Conversation,
  run_id : String,
  terminal_expected : Bool,
  terminal_snapshot_generation? : Int,
) -> Conversation {
  let owned : Array[String] = []
  for input in self.input_ledger {
    if input.kind is SteerInput &&
      input.state is Unconfirmed &&
      input.run_id is Some(owner) &&
      owner == run_id {
      owned.push(input.submission_id)
    }
  }
  if owned.is_empty() {
    return self
  }
  let anchor = self.run_tail_notice_anchor(
    terminal_expected~,
    terminal_snapshot_generation?,
  )
  let overlay = self.overlay.map(notice => {
    let replace = notice.anchor is UncertainTail ||
      (terminal_expected && notice.anchor is SnapshotCut(..))
    if replace {
      match notice.reconciliation {
        Submission(id) if owned.contains(id) => { ..notice, anchor, }
        _ => notice
      }
    } else {
      notice
    }
  })
  { ..self, overlay, }
}

///|
/// Arm only the exact steers captured by one lifecycle frontier. The future
/// snapshot is an observation fence, not evidence that any anonymous User or
/// Terminal belongs to this run; exact receipts may still retract the notice.
fn Conversation::arm_unconfirmed_steers_at_snapshot_cut(
  self : Conversation,
  submission_ids : Array[String],
  owner_run_id : String,
  snapshot_generation : Int,
) -> Conversation {
  let owned : Array[String] = []
  for input in self.input_ledger {
    if input.kind is SteerInput &&
      input.state is Unconfirmed &&
      input.run_id is Some(owner) &&
      owner == owner_run_id &&
      submission_ids.contains(input.submission_id) {
      owned.push(input.submission_id)
    }
  }
  if owned.is_empty() {
    return self
  }
  let overlay = self.overlay.map(notice => {
    match (notice.anchor, notice.reconciliation) {
      (UncertainTail, Submission(id)) if owned.contains(id) =>
        { ..notice, anchor: SnapshotCut(snapshot_generation~) }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// Mark one exact local submission unconfirmed. Legacy receipts have no id and
/// therefore never enter here. The linked notice remains retractable by a late
/// id-bearing receipt, but canonical transcript text cannot claim ownership.
fn Conversation::mark_submission_unconfirmed(
  self : Conversation,
  submission_id : String,
  content : String,
  run_tail : Bool,
  terminal_expected? : Bool = true,
  terminal_snapshot_generation? : Int,
) -> (Conversation, Bool) {
  for index, input in self.input_ledger {
    if input.submission_id == submission_id && input.state is Awaiting {
      let input_ledger = self.input_ledger.copy()
      input_ledger[index] = { ..input, state: Unconfirmed }
      let next = { ..self, input_ledger, }
      if next.has_notice_for_input(submission_id) {
        return (next, true)
      }
      let next = if run_tail {
        next.append_run_tail_notice(
          Assistant(is_danger=true),
          content,
          Submission(submission_id),
          terminal_expected~,
          terminal_snapshot_generation?,
        )
      } else {
        next.append_notice(
          Assistant(is_danger=true),
          content,
          Submission(submission_id),
        )
      }
      return (next, true)
    }
  }
  (self, false)
}

///|
/// Remove one exact id-bearing receipt's ledger entry and provisional notice.
/// `kind` prevents a malformed cross-kind echo from consuming an entry.
fn PendingInput::matches_receipt(
  self : PendingInput,
  submission_id : String,
  kind : InputKind,
  run_id : String?,
) -> Bool {
  guard self.submission_id == submission_id else { return false }
  match kind {
    InitialPrompt => self.kind is InitialPrompt
    SteerInput =>
      self.kind is SteerInput &&
      run_id is Some(run_id) &&
      self.run_id is Some(owner) &&
      owner == run_id
  }
}

///|
fn Conversation::acknowledge_submission(
  self : Conversation,
  submission_id : String,
  kind : InputKind,
  run_id : String?,
) -> (Conversation, Bool) {
  for index, input in self.input_ledger {
    if input.matches_receipt(submission_id, kind, run_id) {
      let input_ledger = self.input_ledger.copy()
      let _ = input_ledger.remove(index)
      let overlay = self.overlay.filter(notice => {
        !(notice.reconciliation is Submission(id) && id == submission_id)
      })
      return ({ ..self, input_ledger, overlay }, true)
    }
  }
  (self, false)
}

///|
/// Attach an accepted initial submission to its run without treating the
/// host's stdin-write response as durable proof. The draft remains recoverable
/// until the run's canonical commit path proves it reached the store.
fn Conversation::bind_initial_submission_to_run(
  self : Conversation,
  submission_id : String,
  run_id : String,
) -> Conversation {
  let input_ledger = self.input_ledger.copy()
  for index, input in input_ledger {
    if input.kind is InitialPrompt && input.submission_id == submission_id {
      input_ledger[index] = { ..input, run_id: Some(run_id) }
      return { ..self, input_ledger, }
    }
  }
  self
}

///|
/// A normal terminal-backed finish proves this exact run got past its durable
/// User append. Retire the bound prompt and any provisional transport notice;
/// transcript content itself is still never used as ownership evidence.
fn Conversation::acknowledge_initial_for_run(
  self : Conversation,
  run_id : String,
) -> Conversation {
  let retired : Array[String] = []
  let input_ledger = self.input_ledger.filter(input => {
    if input.kind is InitialPrompt &&
      input.run_id is Some(owner) &&
      owner == run_id {
      retired.push(input.submission_id)
      false
    } else {
      true
    }
  })
  if retired.is_empty() {
    return self
  }
  let overlay = self.overlay.filter(notice => {
    !(notice.reconciliation is Submission(id) && retired.contains(id))
  })
  { ..self, input_ledger, overlay }
}

///|
/// An abnormal finish does not prove the initial User append succeeded. Keep
/// the exact draft in a truthful, retractable notice instead of consuming it
/// on the earlier stdin-write response.
fn Conversation::mark_initial_for_run_unconfirmed(
  self : Conversation,
  run_id : String,
  durable_frontier? : Int,
  terminal_snapshot_generation? : Int,
) -> Conversation {
  let mut next = self
  for input in self.input_ledger {
    if input.kind is InitialPrompt &&
      input.run_id is Some(owner) &&
      owner == run_id {
      let updated = if input.state is Awaiting {
        let (updated, _) = next.mark_submission_unconfirmed(
          input.submission_id,
          "Prompt delivery could not be confirmed before the run ended — " +
          "check the transcript before resubmitting: " +
          input.draft,
          true,
          terminal_expected=false,
          terminal_snapshot_generation?,
        )
        updated
      } else {
        next
      }
      next = if durable_frontier is Some(frontier) {
        updated.anchor_submission_notice_at_durable_frontier(
          input.submission_id,
          frontier,
        )
      } else if terminal_snapshot_generation is Some(snapshot_generation) {
        updated.anchor_submission_notice_at_snapshot_cut(
          input.submission_id,
          snapshot_generation,
        )
      } else {
        updated
      }
    }
  }
  next
}

///|
/// An EOF frontier of zero, with no applied or buffered commit, proves this
/// session record was never created. This is stronger than an unsuccessful
/// snapshot read: the host observed the writer after process exit.
fn Conversation::is_empty_at_durable_frontier(
  self : Conversation,
  frontier : Int,
) -> Bool {
  let reconciliation_buffer_empty = match self.sync {
    Synced => true
    Reloading(buffered~, ..) => buffered.is_empty()
    ReloadFailed(buffered~, ..) => buffered.is_empty()
  }
  frontier == 0 &&
  self.watermark == 0 &&
  self.messages.is_empty() &&
  reconciliation_buffer_empty
}

///|
/// Recover the exact prompt whose run reached EOF before its first durable
/// append. The draft returns to the composer (without overwriting newer text),
/// exact-id ownership is retired, and the explanation becomes a retained
/// local notice so reconnect never probes a record known not to exist.
fn Conversation::restore_unpersisted_initial_for_run(
  self : Conversation,
  run_id : String,
) -> Conversation {
  for input in self.input_ledger {
    if input.kind is InitialPrompt &&
      input.run_id is Some(owner) &&
      owner == run_id {
      let (restored, _) = self.reject_submission(
        input.submission_id,
        InitialPrompt,
        Some(run_id),
        "The prompt was not saved before the run ended; it has been restored for resubmission.",
      )
      return restored
    }
  }
  self
}

///|
/// Restore a definitively refused submission without overwriting a draft the
/// user typed while the request was in flight. Recovered text is placed first,
/// followed by the newer draft; mention chips retain both submissions' order.
fn Conversation::restore_submission(
  self : Conversation,
  submission : PendingInput,
) -> Conversation {
  let task = if self.task.is_empty() {
    submission.draft
  } else if submission.draft.is_empty() || self.task == submission.draft {
    self.task
  } else {
    submission.draft + "\n\n" + self.task
  }
  let mentions = submission.mentions.copy()
  for mention in self.mentions {
    mentions.push(mention)
  }
  { ..self, task, mentions }
}

///|
/// Recover everything the user can still resubmit when this conversation is
/// archived out from under the composer. Initial prompts still in the local
/// ownership ledger come first in send order, followed by text typed since;
/// no run or receipt state crosses into the replacement conversation.
fn Conversation::archive_salvage(
  self : Conversation,
) -> (String, Array[Mention], Bool) {
  let drafts : Array[String] = []
  let mentions : Array[Mention] = []
  let mut pending_initial = false
  for input in self.input_ledger {
    if input.kind is InitialPrompt {
      pending_initial = true
      if !input.draft.trim().is_empty() {
        drafts.push(input.draft)
      }
      for mention in input.mentions {
        mentions.push(mention)
      }
    }
  }
  if !self.task.trim().is_empty() {
    drafts.push(self.task)
  }
  for mention in self.mentions {
    mentions.push(mention)
  }
  (drafts.join("\n\n"), mentions, pending_initial)
}

///|
/// Retire one definitively refused local submission, restore its composer
/// draft, and replace any provisional notice with one retained explanation.
fn Conversation::reject_submission(
  self : Conversation,
  submission_id : String,
  kind : InputKind,
  run_id : String?,
  notice : String,
) -> (Conversation, Bool) {
  for index, input in self.input_ledger {
    if input.matches_receipt(submission_id, kind, run_id) {
      let input_ledger = self.input_ledger.copy()
      let _ = input_ledger.remove(index)
      let overlay = self.overlay.filter(item => {
        !(item.reconciliation is Submission(id) && id == submission_id)
      })
      let next = { ..self, input_ledger, overlay }
      return (
        next
        .restore_submission(input)
        .append_local_notice(Assistant(is_danger=true), notice),
        true,
      )
    }
  }
  (self, false)
}

///|
/// A connection boundary makes every response still awaiting a receipt
/// indeterminate. Awaiting starts and steers gain exact-id provisional
/// notices.
fn Conversation::mark_awaiting_inputs_unconfirmed(
  self : Conversation,
  snapshot_generation? : Int,
) -> Conversation {
  let mut conv = self
  for input in self.input_ledger {
    if input.state is Awaiting {
      let label = match input.kind {
        InitialPrompt =>
          "Prompt delivery could not be confirmed after reconnect"
        SteerInput => "Steer delivery could not be confirmed after reconnect"
      }
      let (next, _) = conv.mark_submission_unconfirmed(
        input.submission_id,
        label +
        " — check the transcript before resubmitting: " +
        input.content,
        snapshot_generation is Some(_),
        terminal_expected=false,
        terminal_snapshot_generation?=snapshot_generation,
      )
      conv = next
    }
    // A transport failure may already have changed this exact entry to
    // Unconfirmed before the connection boundary. Re-anchor both states:
    // the reconnect snapshot, not the old display length, is the first safe
    // chronology fence for commits received while this page was absent.
    if snapshot_generation is Some(generation) {
      conv = conv.anchor_submission_notice_at_snapshot_cut(
        input.submission_id,
        generation,
      )
    }
  }
  conv
}

///|
/// A run ended before every steer receipt reached this client. Do not guess
/// whether those steers landed: move each awaiting entry to an exact-id,
/// retractable unconfirmed notice that follows the durable run tail. An
/// abnormal EOF supplies an exact sequence because it may have no terminal.
fn Conversation::mark_awaiting_steers_unconfirmed(
  self : Conversation,
  durable_frontier? : Int,
  submission_ids? : Array[String],
  owner_run_id? : String,
  terminal_expected? : Bool = true,
  terminal_snapshot_generation? : Int,
) -> Conversation {
  let mut conv = self
  for input in self.input_ledger {
    let included = match submission_ids {
      Some(ids) => ids.contains(input.submission_id)
      None => true
    }
    let owned = match owner_run_id {
      Some(run_id) => input.run_id is Some(owner) && owner == run_id
      None => true
    }
    if included && owned && input.kind is SteerInput && input.state is Awaiting {
      let (next, _) = conv.mark_submission_unconfirmed(
        input.submission_id,
        steer_unconfirmed_notice(input.content),
        true,
        terminal_expected~,
        terminal_snapshot_generation?,
      )
      conv = if durable_frontier is Some(frontier) {
        next.anchor_submission_notice_at_durable_frontier(
          input.submission_id,
          frontier,
        )
      } else {
        next
      }
    }
  }
  conv
}

///|
/// A different id-bearing Started event in the same session proves an older
/// unconfirmed start can no longer acquire a receipt. Retain its truthful
/// notice but release ownership so repeated uncertain starts cannot accumulate
/// forever.
fn Conversation::retire_unconfirmed_initials_before(
  self : Conversation,
  current_submission_id : String,
) -> Conversation {
  let retired : Array[String] = []
  let input_ledger = self.input_ledger.filter(input => {
    if input.kind is InitialPrompt &&
      input.state is Unconfirmed &&
      input.submission_id != current_submission_id {
      retired.push(input.submission_id)
      false
    } else {
      true
    }
  })
  if retired.is_empty() {
    return self
  }
  let overlay = self.overlay.map(notice => {
    match notice.reconciliation {
      Submission(id) if retired.contains(id) =>
        { ..notice, reconciliation: Retained }
      _ => notice
    }
  })
  { ..self, input_ledger, overlay }
}

///|
/// Append one local notice unless the same text is already present. Reload
/// exhaustion can happen in several rounds; one durable conversation should
/// not accumulate an identical warning for every round.
fn Conversation::append_local_notice_once(
  self : Conversation,
  kind : @transcript.ItemKind,
  content : String,
) -> Conversation {
  for item in self.overlay {
    if item.content == content {
      return self
    }
  }
  self.append_local_notice(kind, content)
}

///|

///|
/// Interleave local notices at their creation boundary. Future durable turns
/// therefore render after an older failure instead of pushing it to the tail.
fn Conversation::visible_items(
  self : Conversation,
) -> Array[@transcript.TranscriptItem] {
  if self.overlay.is_empty() {
    self.messages
  } else {
    let visible : Array[@transcript.TranscriptItem] = []
    for index in 0..<self.messages.length() {
      for notice in self.overlay {
        if notice.anchor is AfterMessages(boundary) && boundary == index {
          visible.push({ kind: notice.kind, content: notice.content })
        }
      }
      visible.push(self.messages[index])
    }
    for notice in self.overlay {
      match notice.anchor {
        TerminalTail(_)
        | PriorTerminalTail(..)
        | SnapshotCut(..)
        | UncertainTail
        | DurableTail(_) =>
          visible.push({ kind: notice.kind, content: notice.content })
        AfterMessages(boundary) if boundary >= self.messages.length() =>
          visible.push({ kind: notice.kind, content: notice.content })
        _ => ()
      }
    }
    visible
  }
}

///|
/// A run-tail or abnormal-EOF notice still lacks a proven chronology boundary.
/// Local submission waits rather than letting a later run make an older
/// missing boundary look like the notice's owner. A bare `UncertainTail`
/// never claims a durable event and has no proof left to wait for; the synced
/// transcript gate is sufficient once its causal recovery read has completed.
fn Conversation::has_unresolved_run_tail_notice(self : Conversation) -> Bool {
  self.overlay
  .iter()
  .any(notice => {
    match notice.anchor {
      TerminalTail(_)
      | PriorTerminalTail(..)
      | SnapshotCut(..)
      | DurableTail(_) => true
      _ => false
    }
  })
}

///|
/// A different run began before older run-tail notices were placed. A normal
/// semantic finish guarantees that its Terminal was durable before Started,
/// so a post-Started full snapshot can still locate the earliest terminal
/// above its floor. An uncertain finish has no such proof and loses its floor
/// immediately; otherwise the successor's terminal could claim it.
fn Conversation::prepare_tail_notices_for_successor(
  self : Conversation,
  snapshot_generation : Int,
) -> Conversation {
  let overlay = self.overlay.map(notice => {
    match notice.anchor {
      TerminalTail(Some(floor)) =>
        { ..notice, anchor: PriorTerminalTail(floor~, snapshot_generation~) }
      TerminalTail(None) | UncertainTail =>
        { ..notice, anchor: SnapshotCut(snapshot_generation~) }
      SnapshotCut(_) => { ..notice, anchor: SnapshotCut(snapshot_generation~) }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// Freeze a current terminal-backed notice whose exclusive sequence floor is
/// crossed by this durable terminal. `PriorTerminalTail` deliberately does
/// not match live commits, while `UncertainTail` never matches any anonymous
/// terminal: either could otherwise claim a successor's terminal.
fn Conversation::freeze_run_tail_notices_at_terminal(
  self : Conversation,
  terminal_sequence : Int,
  boundary : Int,
) -> Conversation {
  let overlay = self.overlay.map(notice => {
    match notice.anchor {
      TerminalTail(Some(floor)) if terminal_sequence > floor =>
        { ..notice, anchor: AfterMessages(boundary) }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// Reconcile terminal-backed notices when a snapshot has already absorbed
/// their terminal commits. An uncertain run is intentionally excluded: if it
/// had no Terminal, the first one above its floor could belong to an entirely
/// missed successor run. `event_boundaries` identifies terminals and carries
/// each projected end because a deduplicated finished terminal may add no
/// display item.
fn Conversation::freeze_run_tail_notices_from_snapshot(
  self : Conversation,
  event_boundaries : Array[(Int, Bool, Int)],
  generation : Int,
) -> Conversation {
  let overlay = self.overlay.map(notice => {
    let floor = match notice.anchor {
      TerminalTail(Some(floor)) => Some(floor)
      PriorTerminalTail(floor~, snapshot_generation~) if generation >=
        snapshot_generation => Some(floor)
      _ => None
    }
    match floor {
      Some(floor) => {
        for event in event_boundaries {
          let (sequence, is_terminal, boundary) = event
          if is_terminal && sequence > floor {
            return { ..notice, anchor: AfterMessages(boundary) }
          }
        }
        notice
      }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// A gap-free snapshot whose read began after an uncertain lifecycle event is
/// a safe display fence even though it cannot identify which stored items
/// belong to that run. Anchor at the snapshot cut itself, before commits that
/// arrived later and were drained from the live buffer.
fn Conversation::freeze_snapshot_cut_notices_from_snapshot(
  self : Conversation,
  generation : Int,
  boundary : Int,
) -> Conversation {
  let overlay = self.overlay.map(notice => {
    match notice.anchor {
      SnapshotCut(snapshot_generation~) if generation >= snapshot_generation =>
        { ..notice, anchor: AfterMessages(boundary) }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// A causal, gap-free snapshot should contain every terminal guaranteed before
/// its Started boundary. If it does not, stop matching that notice rather than
/// letting a future run's terminal claim it. The snapshot itself is still a
/// safe observation fence; exact-id ownership remains, so a later receipt can
/// retract the notice and `agent.durable` can still move it to an exact cut.
fn Conversation::abandon_missing_prior_terminals(
  self : Conversation,
  generation : Int,
  boundary : Int,
) -> Conversation {
  let overlay = self.overlay.map(notice => {
    match notice.anchor {
      PriorTerminalTail(snapshot_generation~, ..) if generation >=
        snapshot_generation => { ..notice, anchor: AfterMessages(boundary) }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// Resolve abnormal-EOF notices when their exact final sequence is applied
/// incrementally. Unlike a normal finish, the boundary event may be a User,
/// assistant, tool result, or no-op projection rather than a Terminal.
fn Conversation::freeze_durable_tail_notices_at_commit(
  self : Conversation,
  sequence : Int,
  boundary : Int,
) -> Conversation {
  let overlay = self.overlay.map(notice => {
    match notice.anchor {
      DurableTail(frontier) if sequence == frontier =>
        { ..notice, anchor: AfterMessages(boundary) }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// Resolve the same exact sequence when a snapshot has already absorbed the
/// buffered commit. Every stored event carries its projected end, including
/// events that add no visible item.
fn Conversation::freeze_durable_tail_notices_from_snapshot(
  self : Conversation,
  event_boundaries : Array[(Int, Bool, Int)],
) -> Conversation {
  let overlay = self.overlay.map(notice => {
    match notice.anchor {
      DurableTail(frontier) => {
        for event in event_boundaries {
          let (sequence, _, boundary) = event
          if sequence == frontier {
            return { ..notice, anchor: AfterMessages(boundary) }
          }
        }
        notice
      }
      _ => notice
    }
  })
  { ..self, overlay, }
}

///|
/// Apply one durable commit's item to the transcript. Local notices have no
/// durable twin and are therefore never retired by item class. Returns
/// whether the durable transcript visibly grew.
fn Conversation::apply_commit(
  self : Conversation,
  sequence : Int,
  kind : String,
  payload : Map[String, Json],
) -> (Bool, Conversation) {
  // A canonical User is transcript data, never local-submission ownership.
  // It is not a run boundary: the same kind also stores in-run steering.
  let messages = self.messages.copy()
  let before = messages.length()
  @transcript.apply_session_item(messages, kind, payload)
  let conv = {
    ..self,
    messages,
    run_durable_floor: if !(self.run is NoRun(..)) &&
      self.run_durable_floor is None &&
      self.run_floor_generation is None &&
      kind != "terminal" {
      Some(self.last_terminal_sequence)
    } else {
      self.run_durable_floor
    },
    last_terminal_sequence: if kind == "terminal" &&
      sequence > self.last_terminal_sequence {
      sequence
    } else {
      self.last_terminal_sequence
    },
  }
  let conv = if kind == "terminal" {
    conv.freeze_run_tail_notices_at_terminal(sequence, messages.length())
  } else {
    conv
  }
  let conv = conv.freeze_durable_tail_notices_at_commit(
    sequence,
    messages.length(),
  )
  (messages.length() > before, conv)
}

///|
/// Start one reload unless this conversation already has a request in flight.
/// Tokens come from the model rather than the conversation: a pruned or
/// archived conversation can therefore be recreated without accepting a late
/// reply issued to its earlier incarnation. Buffered commits from an exhausted
/// retry round carry into the next one.
fn Model::begin_transcript_reload(
  self : Model,
  conv : Conversation,
) -> (Model, Int?) {
  match conv.sync {
    Reloading(..) => (self.replace_conversation(conv), None)
    Synced => {
      let generation = self.transcript_request_generation + 1
      (
        {
          ..self.replace_conversation({
            ..conv,
            sync: Reloading(
              generation~,
              attempt=1,
              buffered=[],
              reload_after_current=false,
            ),
          }),
          transcript_request_generation: generation,
        },
        Some(generation),
      )
    }
    ReloadFailed(buffered~, ..) => {
      let generation = self.transcript_request_generation + 1
      (
        {
          ..self.replace_conversation({
            ..conv,
            sync: Reloading(
              generation~,
              attempt=1,
              buffered=buffered.copy(),
              reload_after_current=false,
            ),
          }),
          transcript_request_generation: generation,
        },
        Some(generation),
      )
    }
  }
}

///|
/// Require a snapshot whose read cut starts after the current transition.
/// An existing read stays single-flight but is followed by one fresh
/// generation; otherwise start that generation now.
fn Model::ensure_transcript_reload_after_current(
  self : Model,
  conv : Conversation,
) -> (Model, Int?) {
  match conv.sync {
    Reloading(generation~, attempt~, buffered~, reload_after_current=false) =>
      (
        self.replace_conversation({
          ..conv,
          sync: Reloading(
            generation~,
            attempt~,
            buffered~,
            reload_after_current=true,
          ),
        }),
        None,
      )
    Reloading(reload_after_current=true, ..) =>
      (self.replace_conversation(conv), None)
    Synced | ReloadFailed(..) => self.begin_transcript_reload(conv)
  }
}

///|
/// Buffer a commit while a snapshot generation is unresolved. The array is
/// copied so earlier Rabbita model snapshots remain immutable. Buffered
/// terminals do not advance the applied terminal frontier: an earlier
/// non-terminal must still capture the frontier that preceded it when the
/// sorted buffer is eventually drained.
fn Conversation::buffer_commit(
  self : Conversation,
  commit : BufferedCommit,
) -> Conversation {
  match self.sync {
    Reloading(generation~, attempt~, buffered~, reload_after_current~) => {
      let buffered = buffered.copy()
      buffered.push(commit)
      {
        ..self,
        sync: Reloading(generation~, attempt~, buffered~, reload_after_current~),
      }
    }
    ReloadFailed(generation~, buffered~) => {
      let buffered = buffered.copy()
      buffered.push(commit)
      { ..self, sync: ReloadFailed(generation~, buffered~) }
    }
    Synced => self
  }
}

///|
/// Whether this client has already applied or buffered a durable sequence.
/// The store may rebroadcast a commit, so callers that attach one-time work
/// to its first observation must check both the applied watermark and the
/// unresolved snapshot buffer.
fn Conversation::has_seen_durable_sequence(
  self : Conversation,
  sequence : Int,
) -> Bool {
  if sequence <= self.watermark {
    return true
  }
  match self.sync {
    Reloading(buffered~, ..) | ReloadFailed(buffered~, ..) =>
      buffered.iter().any(commit => commit.sequence == sequence)
    Synced => false
  }
}

///|
/// Adopt a fresh `session.load` snapshot: it replaces the durable transcript
/// wholesale, preserves client-local notices, and drains commits buffered
/// while the read was in flight. The caller has already checked generation
/// and watermark monotonicity. Returns whether buffered commits from beyond
/// the snapshot failed to connect — a remaining gap answered by a new read.
fn Conversation::adopt_snapshot(
  self : Conversation,
  items : Array[@transcript.TranscriptItem],
  watermark : Int,
  event_boundaries : Array[(Int, Bool, Int)],
) -> (Conversation, Bool) {
  let (generation, pending) = match self.sync {
    Reloading(generation~, buffered~, ..) => (generation, buffered.copy())
    _ => return (self, false)
  }
  // Sequence order, whatever the arrival order was.
  pending.sort_by((a, b) => a.sequence - b.sequence)
  let snapshot_boundary = items.length()
  // This one local notice represents the reload state itself, so a current
  // successful snapshot clears it by exact identity. Every unrelated local
  // notice survives unchanged.
  let mut last_terminal_sequence = self.last_terminal_sequence
  let mut snapshot_terminal_sequence = 0
  let mut snapshot_terminal_boundary = 0
  for boundary in event_boundaries {
    let (sequence, is_terminal, item_count) = boundary
    if is_terminal && sequence > snapshot_terminal_sequence {
      snapshot_terminal_sequence = sequence
      snapshot_terminal_boundary = item_count
      if sequence > last_terminal_sequence {
        last_terminal_sequence = sequence
      }
    }
  }
  let floor_snapshot_is_causal = match self.run_floor_generation {
    Some(required) => generation >= required
    None => true
  }
  let reconciled = {
      ..self,
      last_terminal_sequence,
      // A foreign/mid-run Started intentionally leaves the floor unknown. It
      // becomes steerable only when the snapshot visibly has current-run data
      // after its last terminal; a snapshot ending at a terminal may instead
      // have beaten the lifecycle Finished event and proves no open floor.
      run_durable_floor: if !(self.run is NoRun(..)) &&
        self.run_durable_floor is None &&
        floor_snapshot_is_causal &&
        items.length() > snapshot_terminal_boundary {
        Some(snapshot_terminal_sequence)
      } else {
        self.run_durable_floor
      },
      run_floor_generation: if floor_snapshot_is_causal {
        None
      } else {
        self.run_floor_generation
      },
    }
    .freeze_run_tail_notices_from_snapshot(event_boundaries, generation)
    .freeze_durable_tail_notices_from_snapshot(event_boundaries)
  let overlay = reconciled.overlay.filter(item => {
    item.content != TranscriptRefreshFailedNotice
  })
  let mut conv : Conversation = {
    ..reconciled,
    messages: items,
    watermark,
    overlay,
    sync: Synced,
  }
  let leftover : Array[BufferedCommit] = []
  for commit in pending {
    if commit.sequence <= conv.watermark {
      continue
    }
    if commit.sequence == conv.watermark + 1 && leftover.is_empty() {
      let (_, next) = conv.apply_commit(
        commit.sequence,
        commit.kind,
        commit.payload,
      )
      conv = { ..next, watermark: commit.sequence }
    } else {
      leftover.push(commit)
    }
  }
  if leftover.is_empty() {
    // Only a complete causal cut may give up on a supposedly guaranteed old
    // terminal. Do this after the ordered buffer has drained; a gap schedules
    // another snapshot and must keep every proof obligation intact.
    (
      conv
      .freeze_snapshot_cut_notices_from_snapshot(generation, snapshot_boundary)
      .abandon_missing_prior_terminals(generation, snapshot_boundary),
      false,
    )
  } else {
    let conv = if !(conv.run is NoRun(..)) {
      {
        ..conv,
        run_durable_floor: None,
        // The incomplete cut cannot establish this open run's predecessor.
        // The retry generation is necessarily newer than this one.
        run_floor_generation: Some(generation + 1),
      }
    } else {
      conv
    }
    ({ ..conv, sync: ReloadFailed(generation~, buffered=leftover) }, true)
  }
}

///|
/// The transcript notice for steering input that never reached the turn —
/// whether the engine rejected it (it raced the turn's end through the
/// pipes) or the run died with it unsettled. Either way the text must not
/// vanish silently.
fn steer_dropped_notice(text : String) -> String {
  "Input was not delivered (the task ended as you sent it) — submit it again: \{text}"
}

///|
/// The truthful notice for a steer whose receipt was lost at a run boundary.
/// It intentionally does not claim the steer was dropped: a later exact-id
/// receipt may still prove either outcome.
fn steer_unconfirmed_notice(text : String) -> String {
  "Steer delivery could not be confirmed — check the transcript before resubmitting: \{text}"
}

///|
/// Severity of a status, used only to pick a CSS accent class.
priv enum StatusKind {
  Neutral
  Ok
  Warn
  Danger
}

///|
fn StatusKind::css(self : StatusKind) -> String {
  match self {
    Neutral => ""
    Ok => "ok"
    Warn => "warn"
    Danger => "danger"
  }
}

///|
/// How a run ended, parsed from the engine's wire status. An unrecognized
/// wire value survives as `Unknown` — a newer engine's statuses still get a
/// label, they just fall on the cautious side of every typed split.
priv enum RunOutcome {
  Completed
  ContextYield
  Aborted
  RunFailed
  Cancelled
  MaxStepsExhausted
  Unknown(String)
} derive(Eq)

///|
fn RunOutcome::parse(wire : String) -> RunOutcome {
  match wire {
    "finished" => Completed
    "context_yield" => ContextYield
    "aborted" => Aborted
    "failed" => RunFailed
    "cancelled" => Cancelled
    "max_steps_exhausted" => MaxStepsExhausted
    other => Unknown(other)
  }
}

///|
fn RunOutcome::label(self : RunOutcome) -> String {
  match self {
    Completed => "Finished"
    ContextYield => "Context limit reached"
    Aborted => "Aborted"
    RunFailed => "Failed"
    Cancelled => "Cancelled"
    MaxStepsExhausted => "Max steps exhausted"
    // An empty wire status reads as a plain finish, like `parse`'s inverse.
    Unknown(wire) => if wire.trim().is_empty() { "Finished" } else { wire }
  }
}

///|
/// What the top bar shows, purely a display projection: `display_status`
/// derives it per render from the bridge state, the active conversation's
/// run phase, and the settings — nothing stores a `Status`, so the label and
/// its severity cannot drift from the state they describe.
priv enum Status {
  WaitingBridge
  Ready
  SetupRequired
  ApiKeyRequired
  Starting
  Running
  Cancelling
  // The engine's 1-based step counter; `None` for an engine build that does
  // not number its steps.
  Step(Int?)
  Failed
  Errored
  Finished(RunOutcome)
  Unavailable(String)
}

///|
fn Status::label(self : Status) -> String {
  match self {
    WaitingBridge => "Waiting for bridge"
    Ready => "Ready"
    SetupRequired => "Setup required"
    ApiKeyRequired => "API key required"
    Starting => "Starting"
    Running => "Running"
    Cancelling => "Cancelling"
    Step(step) => if step is Some(step) { "Step \{step}" } else { "Step" }
    Failed => "Failed"
    Errored => "Error"
    Finished(outcome) => outcome.label()
    Unavailable(message) => message
  }
}

///|
fn Status::kind(self : Status) -> StatusKind {
  match self {
    WaitingBridge => Neutral
    Ready => Ok
    SetupRequired
    | ApiKeyRequired
    | Starting
    | Running
    | Cancelling
    | Step(_) => Warn
    Failed | Errored | Unavailable(_) => Danger
    Finished(outcome) => if outcome is Completed { Ok } else { Warn }
  }
}
