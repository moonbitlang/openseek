///|
/// Which model a conversation's turns run with. The composer's shared selector
/// offers the DeepSeek service tiers or the GLM models, following the
/// configured provider; `Other` retains a wire name this build does not know —
/// a run started with `OPENSEEK_MODEL` set, or a newer engine's model echoed
/// back by `agent.started` — so the chip reports what the engine actually ran
/// instead of a tier it never used.
priv enum EngineModel {
  DsPro
  DsFlash
  Glm53
  Glm53Flash
  Other(String)
} derive(Eq, Debug)

///|
fn EngineModel::wire(self : EngineModel) -> String {
  match self {
    DsPro => "deepseek-v4-pro"
    DsFlash => "deepseek-v4-flash"
    Glm53 => "glm-5.3"
    Glm53Flash => "glm-5.3-flash"
    Other(name) => name
  }
}

///|
/// Read a wire name. A blank one is the absence of a model, not a tier, so it
/// reads as `None` — stored preferences fall back to what they already had,
/// and the event decoders treat it like the missing field it is.
fn EngineModel::parse(value : String) -> EngineModel? {
  match value.trim().to_owned() {
    "deepseek-v4-pro" => Some(DsPro)
    "deepseek-v4-flash" => Some(DsFlash)
    "glm-5.3" => Some(Glm53)
    "glm-5.3-flash" => Some(Glm53Flash)
    "" => None
    name => Some(Other(name))
  }
}

///|
/// The product-facing model name shown on the composer chip. An unknown model
/// keeps its wire name, so a custom endpoint never renders as a blank label.
fn EngineModel::label(self : EngineModel) -> String {
  match self {
    DsPro => "DS Pro"
    DsFlash => "DS Flash"
    Glm53 => "GLM 5.3"
    Glm53Flash => "GLM 5.3 Flash"
    Other(name) => name
  }
}

///|
/// Whether this Desktop model is one whose request format accepts the
/// `no`/`high`/`max` reasoning setting: the DeepSeek models, and the GLM
/// models (the engine maps `no` to GLM's lowest supported effort, because
/// GLM 5.3 always reasons). Unknown models include providers such as Kimi,
/// where sending this setting would claim a capability the model does not
/// expose.
fn EngineModel::supports_reasoning(self : EngineModel) -> Bool {
  match self {
    DsPro | DsFlash | Glm53 | Glm53Flash => true
    Other(_) => false
  }
}

///|
/// OpenSeek's reasoning choices. These stay distinct from Codex catalog
/// values: the two agents share the control and request lifecycle, while
/// each agent sends only values its own service defines.
priv enum OpenSeekReasoning {
  ReasoningOff
  ReasoningHigh
  ReasoningMax
} derive(Eq)

///|
fn OpenSeekReasoning::wire(self : OpenSeekReasoning) -> String {
  match self {
    ReasoningOff => "no"
    ReasoningHigh => "high"
    ReasoningMax => "max"
  }
}

///|
/// Convert the UI choice into the closed OpenSeek command value. Storage keeps
/// the UI enum's string representation, while requests cross the Desktop JSON
/// boundary with the protocol-owned type.
fn OpenSeekReasoning::protocol(
  self : OpenSeekReasoning,
) -> @protocol.OpenSeekThinking {
  match self {
    ReasoningOff => ThinkingOff
    ReasoningHigh => ThinkingHigh
    ReasoningMax => ThinkingMax
  }
}

///|
fn OpenSeekReasoning::parse(value : String) -> OpenSeekReasoning? {
  match value.trim().to_owned() {
    "no" => Some(ReasoningOff)
    "high" => Some(ReasoningHigh)
    "max" => Some(ReasoningMax)
    _ => None
  }
}

///|
fn OpenSeekReasoning::label(self : OpenSeekReasoning) -> String {
  match self {
    ReasoningOff => "Off"
    ReasoningHigh => "High"
    ReasoningMax => "Max"
  }
}

///|
/// GLM cannot turn thinking off: the shared lowest wire choice becomes its
/// `low` effort, so the chip must not promise an unavailable Off state.
fn OpenSeekReasoning::label_for_model(
  self : OpenSeekReasoning,
  model : EngineModel,
) -> String {
  if model is (Glm53 | Glm53Flash) && self is ReasoningOff {
    "Low"
  } else {
    self.label()
  }
}

///|
/// Encode a reasoning setting only for models that advertise it in this UI.
/// Unknown providers keep the field absent, matching the hidden selector.
fn EngineModel::thinking(
  self : EngineModel,
  reasoning : OpenSeekReasoning,
) -> @protocol.OpenSeekThinking? {
  if self.supports_reasoning() {
    Some(reasoning.protocol())
  } else {
    None
  }
}

///|
/// One conversation's remembered tier. `ConversationKey` is a frontend value
/// that deliberately never crosses a boundary, so persistence spells the same
/// identity out itself: the channel's stable URI authority joined to the
/// session id, which keeps two hosts' identical session ids apart.
priv struct StoredConversationModel {
  key : String
  model : EngineModel
} derive(Eq, Debug)

///|
fn conversation_model_key(
  channel : @interop.ChannelId,
  session : String,
) -> String {
  "\{channel.uri_authority()}/\{session}"
}

///|
test "engine models round-trip their wire names" {
  inspect(
    EngineModel::parse("deepseek-v4-pro").unwrap().label(),
    content="DS Pro",
  )
  inspect(
    EngineModel::parse("deepseek-v4-flash").unwrap().label(),
    content="DS Flash",
  )
  inspect(EngineModel::parse("glm-5.3").unwrap().label(), content="GLM 5.3")
  inspect(
    EngineModel::parse("glm-5.3-flash").unwrap().wire(),
    content="glm-5.3-flash",
  )
  assert_true(EngineModel::parse("glm-5.3") is Some(Glm53))
  assert_true(EngineModel::Glm53Flash.supports_reasoning())
  inspect(
    EngineModel::parse(" custom-model ").unwrap().wire(),
    content="custom-model",
  )
  assert_true(EngineModel::parse("  ") is None)
}

///|
/// Viewports at most this wide (CSS pixels) get the narrow layout. Must
/// match the `@media (max-width: …)` breakpoint in index.html.
const NarrowBreakpoint : Int = 760

///|
const DefaultMaxSteps : String = "1000"

///|
const TranscriptRefreshFailedNotice : String = "Transcript refresh failed repeatedly. New commits are buffered; reopen the conversation or wait for the next update to retry."

///|
/// The report for steering input that never reached the turn — whether the
/// engine rejected it (it raced the turn's end through the pipes) or the run
/// died with it unsettled. Either way the text must not vanish silently, and
/// it does not: the refusal puts it back in the composer.
const SteerDroppedNotice : String = "Input was not delivered (the task ended as you sent it) — it is back in the composer."

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
const NotificationCornerStorageKey : String = "openseek.notification_corner"

///|
/// Where the editor panel's file tree docks (bottom panel / right sidebar).
const TreeLayoutStorageKey : String = "openseek.tree_layout"

///|
/// The page-local appearance override. An absent value keeps following the
/// host color scheme until the user chooses a theme in Settings.
const ThemeStorageKey : String = "openseek.theme"

///|
const FpsOverlayStorageKey : String = "openseek.fps_overlay"

///|
/// The page-local monospace family shared by code content, the editor, and the
/// terminal. The value is a fixed choice rather than arbitrary CSS so stored
/// input can never become a style injection surface.
const AppFontStorageKey : String = "openseek.font"

///|
/// The page-local type scale shared by the app chrome, editor, and terminal.
const AppFontSizeStorageKey : String = "openseek.font_size"

///|
/// The tier new conversations are born with — the last one picked in the
/// composer, and the fallback for a conversation nothing remembers.
const ModelStorageKey : String = "openseek.model"

///|
/// The agent the next "New chat" starts with — whichever provider group the
/// unified model chip was last picked from.
const AgentStorageKey : String = "openseek.agent"

///|
/// The Codex model id the next Codex thread or turn starts with. Codex's own
/// catalog default applies when this is absent or no longer listed.
const CodexModelStorageKey : String = "openseek.codex_model"

///|
/// The Codex reasoning effort the next ordinary turn starts with. The fetched
/// model catalog validates it before the frontend sends it to app-server.
const CodexReasoningEffortStorageKey : String = "openseek.codex_reasoning_effort"

///|
/// The OpenSeek reasoning choice used by the next start, compaction, or goal
/// request. It is page-local like the model choice and separate from Codex's
/// catalog-backed setting because their supported wire values differ.
const OpenSeekReasoningStorageKey : String = "openseek.reasoning_effort"

///|
/// GLM has forced thinking, so its lightweight default and later choices are
/// kept apart from DeepSeek's reasoning preference. A user who wants Max for
/// DeepSeek should not inherit it merely by switching the endpoint to GLM.
const GlmReasoningStorageKey : String = "openseek.glm_reasoning_effort"

///|
/// Every conversation whose tier the user has chosen, so reopening one
/// recovers its own tier instead of inheriting whatever was picked last in
/// some unrelated chat. Page-local like the rest of this file: the desktop
/// window and a browser console remember separately, and the host never sees
/// this. Rows are newest first.
const ConversationModelsStorageKey : String = "openseek.conversation_models"

///|
/// How many conversations remember their tier. Conversations are unbounded
/// and this is one localStorage value, so the list is capped; past the cap
/// the least recently chosen conversation forgets and opens on the default,
/// exactly like one the user never chose a tier for.
const ConversationModelsLimit : Int = 200

///|
/// Obsolete: each workspace's launch-mode default lives in its own
/// `.openseek/settings.json` now. The key is kept only so startup can
/// delete whatever old builds stored.
const WorkspaceDefaultModeStorageKey : String = "openseek.workspace_default_mode"

///|
/// Obsolete: the update channel is gone — there is one release stream. The
/// key is kept only so startup can delete whatever old builds stored.
const UpdateChannelStorageKey : String = "openseek.update_channel"

///|
/// The app's appearance choice. System preference is tracked separately on
/// the model so this enum always describes exactly what Settings displays.
priv enum Theme {
  System
  Light
  Dark
} derive(Eq)

///|
fn Theme::is_dark(self : Theme, system_dark : Bool) -> Bool {
  match self {
    System => system_dark
    Light => false
    Dark => true
  }
}

///|
/// Unknown or absent stored values deliberately retain the current selection,
/// so old/corrupt page storage cannot force an arbitrary palette.
fn Theme::parse(value : String, fallback : Theme) -> Theme {
  match value {
    "system" => System
    "light" => Light
    "dark" => Dark
    _ => fallback
  }
}

///|
fn Theme::wire(self : Theme) -> String {
  match self {
    System => "system"
    Light => "light"
    Dark => "dark"
  }
}

///|
/// The monospace family selected in Settings. The system stack is the default;
/// Geist remains available as an offline bundled alternative.
priv enum AppFont {
  GeistMono
  SystemMono
  Menlo
} derive(Eq)

///|
/// Unknown or absent stored values retain the current choice, so a stale
/// localStorage value cannot silently replace the active system default.
fn AppFont::parse(value : String, fallback : AppFont) -> AppFont {
  match value {
    "geist-mono" => GeistMono
    "system-mono" => SystemMono
    "menlo" => Menlo
    _ => fallback
  }
}

///|
fn AppFont::wire(self : AppFont) -> String {
  match self {
    GeistMono => "geist-mono"
    SystemMono => "system-mono"
    Menlo => "menlo"
  }
}

///|
/// The concrete CSS family list also feeds xterm and the editor's measured
/// font option, whose imperative widgets cannot inherit the app variable.
fn AppFont::css_family(self : AppFont) -> String {
  match self {
    GeistMono =>
      "\"Geist Mono\", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace"
    SystemMono =>
      "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace"
    Menlo =>
      "Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace"
  }
}

///|
/// The base text size selected in Settings. The CSS token scale derives the
/// surrounding app sizes from this choice; the editor and terminal receive
/// the adjacent smaller pixel value because their glyphs look larger.
priv struct AppFontSize(Int) derive(Eq, Debug)

///|
const AppFontSizeMinPixels : Int = 12

///|
const AppFontSizeMaxPixels : Int = 18

///|
/// Invalid ephemeral localStorage values retain the current readable choice.
fn AppFontSize::parse(value : String, fallback : AppFontSize) -> AppFontSize {
  let pixels = @string.parse_int(value) catch { _ => return fallback }
  if pixels >= AppFontSizeMinPixels && pixels <= AppFontSizeMaxPixels {
    AppFontSize(pixels)
  } else {
    fallback
  }
}

///|
fn AppFontSize::wire(self : AppFontSize) -> String {
  let AppFontSize(pixels) = self
  pixels.to_string()
}

///|
fn AppFontSize::base_pixels(self : AppFontSize) -> Int {
  let AppFontSize(pixels) = self
  pixels
}

///|
/// Measured monospace surfaces use one pixel less than the selected app base.
/// Their larger-looking glyphs then align with surrounding system-sans text.
fn AppFontSize::pixels(self : AppFontSize) -> Double {
  (self.base_pixels() - 1).to_double()
}

///|
/// Which chat-completions endpoint the engine talks to. SeekMoon runs are
/// bring-your-own-key only: the hosted proxy is retired. `Deepseek` is the
/// official endpoint and needs the user's own key; `Custom` is any other
/// OpenAI-compatible endpoint, whose key is optional. The retired hosted
/// names (`openseek` / `openseek-staging`) parse as `Deepseek` so old
/// stores and old clients land on the BYOK default instead of wedging.
/// The setting (and its credentials) live on the host; this mirror is what
/// `settings.get`/`set` replies and the `settings.changed` broadcast last
/// reported.
priv enum ApiProvider {
  Deepseek
  Glm
  Custom
} derive(Eq)

///|
priv enum FollowupBehavior {
  FollowupSteer
  FollowupQueue
} derive(Eq)

///|
fn FollowupBehavior::parse(value : String) -> FollowupBehavior {
  if value == "queue" {
    FollowupQueue
  } else {
    FollowupSteer
  }
}

///|
fn FollowupBehavior::wire(self : FollowupBehavior) -> String {
  match self {
    FollowupSteer => "steer"
    FollowupQueue => "queue"
  }
}

///|
fn ApiProvider::wire(self : ApiProvider) -> String {
  match self {
    Deepseek => "deepseek"
    Glm => "glm"
    Custom => "custom"
  }
}

///|
/// Unknown stored values fall back to the default provider, so a downgrade
/// (or a corrupted store) degrades to the BYOK default instead of wedging
/// the app.
fn ApiProvider::parse(value : String) -> ApiProvider {
  match value.trim().to_owned() {
    "openseek" | "openseek-staging" | "deepseek" => Deepseek
    "glm" => Glm
    "custom" => Custom
    _ => Deepseek
  }
}

///|
/// The model a fresh conversation starts from when the selected provider and
/// the page's last model choice belong to different known model families.
fn ApiProvider::default_model(self : ApiProvider) -> EngineModel {
  match self {
    Deepseek | Custom => DsFlash
    Glm => Glm53
  }
}

///|
/// Whether a known model belongs to the official provider. Custom endpoints
/// deliberately accept every model, and an unknown wire name stays pinned so
/// a newer engine's model is never silently replaced by an older frontend.
fn EngineModel::matches_provider(
  self : EngineModel,
  provider : ApiProvider,
) -> Bool {
  match (provider, self) {
    (Custom, _) | (_, Other(_)) => true
    (Deepseek, DsPro | DsFlash) | (Glm, Glm53 | Glm53Flash) => true
    _ => false
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
  // snapshot from adjudicating a newer start merely because both were once
  // in flight.
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
  model : EngineModel
  max_steps : Int
  session_root : @common.Uri?
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
}

///|
/// One standing permission question, routed back to its conversation. The
/// question itself is the same value the live event produces; only the session
/// it belongs to has to travel beside it, since `PendingApproval` lives inside
/// a conversation and does not name one.
priv struct RecoveredApproval {
  session : String
  approval : PendingApproval
}

///|
/// The exact per-session lifecycle state at the instant an `agent.runs`
/// request starts. An unversioned positive row is safe to replay only while
/// the session still has this state; a live Started or Finished received
/// meanwhile takes precedence over the older snapshot.
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
  // The permission question this page was showing when the request began, if
  // any. A snapshot that does not list it proves it was answered while this
  // page was away — but only for THIS id: a question asked after the request
  // went out is not in the reply either, and clearing that one would take a
  // live card off screen and leave the turn blocked with nothing to press.
  pending_approval_id : String?
}

///|
/// How a recovered settlement matched the request-time owner: by the run it
/// names, or by the submission of a prompt still in flight when the request
/// began.
priv enum SettlementFrontierMatch {
  SettlementByRun
  SettlementBySubmission(String)
}

///|
/// The directory context a conversation belongs to. `Project` names a
/// registered project root. `Worktree` retains both its owning project and
/// registry name; the checkout path itself remains registry-owned and is
/// resolved only when an up-to-date row is available.
///
/// Every conversation has one. Which *directory* it resolves to can still be
/// unknown while the worktree registry is in flight — that is
/// `Model::conversation_placement`'s option, not this one.
priv enum Workspace {
  Project(root~ : @common.Uri)
  Worktree(project~ : @common.Uri, name~ : String)
} derive(Eq, Debug)

///|
/// Which durable twin owns the transcript currently represented here.
/// Archived records may be displayed, but actions that append to a record
/// must reject `ArchivedRecord` in update even when no composer is rendered.
priv enum ConversationRecord {
  LiveRecord
  ArchivedRecord
} derive(Eq)

///|
/// The registered project that owns this workspace.
fn Workspace::project(self : Workspace) -> @common.Uri {
  match self {
    Project(root~) => root
    Worktree(project~, ..) => project
  }
}

///|
/// The worktree registry name, present only for a worktree workspace.
fn Workspace::worktree_name(self : Workspace) -> String? {
  match self {
    Worktree(name~, ..) => Some(name)
    Project(..) => None
  }
}

///|
/// Reasoning visible before its durable assistant event lands.
priv struct LiveReasoning {
  content : String
  complete : Bool
} derive(Eq, Debug)

///|
/// Everything that belongs to one turn and to nothing outside it.
///
/// It is replaced wholesale when a run opens, so a fragment or token count
/// left by the previous turn cannot survive into this one by being forgotten -
/// the reset is one assignment rather than three. Only the `agent.*` lifecycle
/// and stream events write it. Durable commits are deliberately not allowed to
/// mutate it: they carry no run or step identity, so a delayed older commit
/// cannot safely settle a newer stream.
priv struct RunState {
  // Live text of the in-flight assistant turn, accumulated from
  // `assistant_delta` events and cleared by ordered full semantic, step,
  // run-lifecycle, or reconnect boundaries. Follower commits are not run/step
  // tagged and therefore never clear a potentially newer stream. `None` is
  // not streaming — the one place this client shows text the durable record
  // has not committed yet, and the only reason it is a separate field from
  // `messages` rather than a row inside it.
  streaming_response : String?
  // Provisional reasoning assembled from `reasoning_delta`. The completed
  // semantic event seals the buffer. The durable Assistant commit remains the
  // sole history; rendering de-duplicates an equal completed preview without
  // letting the untagged commit mutate this run-scoped state.
  live_reasoning : LiveReasoning?
  // Highest durable event already known when this run opened. Only reasoning
  // committed after this frontier can visually de-duplicate this run's sealed
  // preview; identical text from an earlier turn is unrelated.
  reasoning_frontier : Int
  // Sub-runs this turn has in flight, in the order they started. Live-only:
  // nothing persists a sub-run's progress, so a reload mid-turn shows the
  // tool call pending with no lane under it.
  subruns : Array[@subrun.Lane]
  usage_tokens : Int
} derive(Eq)

///|
/// The state a turn starts from. A conversation with no run open holds one
/// too: every field means "nothing observed".
fn RunState::empty() -> RunState {
  {
    streaming_response: None,
    live_reasoning: None,
    reasoning_frontier: 0,
    subruns: [],
    usage_tokens: 0,
  }
}

///|
fn RunState::for_run(reasoning_frontier : Int) -> RunState {
  { ..RunState::empty(), reasoning_frontier, }
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
  // Live records accept engine mutations. An archived record is a read-only
  // snapshot source until an unarchive notification moves it back to live.
  record : ConversationRecord
  // Registered project or project-owned worktree. One value keeps those
  // mutually exclusive placements from drifting apart and is the only stored
  // source for filesystem and language-server routing.
  workspace : Workspace
  // The composer's launch mode for a conversation that has not begun: run
  // the first prompt in a fresh host-named worktree instead of the
  // workspace root. Consumed by the create-then-start chain, which sets
  // `worktree` and clears this.
  worktree_mode : Bool
  // The model this conversation's next turn runs with, chosen on the
  // composer's chip. Per conversation, not per app: a long refactor can sit
  // on the high tier while a quick question beside it stays cheap. Born from
  // the page's `default_model` — or, for a conversation the page first meets
  // through a live run, from that run's tier. Nothing but the chip changes it
  // afterwards: a start is always older than the composer, so echoing one
  // back would undo a choice the user has already made for the next turn.
  engine_model : EngineModel
  // Root-authored prompt snapshot for submission and delivery recovery. The
  // live textarea value is component-local and is copied here atomically only
  // when the user submits; a rejection may write recovered text back here.
  task : String
  // Root-authored mention snapshot paired with `task`. Editor comments and
  // recovery can add chips here; ordinary local chip edits stay in the
  // component until submission.
  mentions : Array[Mention]
  // Whether the component-local composer currently holds unsent writing.
  // Only empty/non-empty transitions update this flag; the text itself stays
  // outside the root Model. It keeps a fresh conversation reachable when the
  // user switches away without putting every keystroke through root update.
  composer_draft_present : Bool
  // Where this conversation's run stands; see `RunPhase`. Replaces the old
  // `running`/`active_run_id`/`status` trio, whose redundant encodings could
  // drift apart (running with no id was "starting" only by convention).
  run : RunPhase
  // The most recent run id this conversation has owned, kept after the run
  // finishes. Compaction is requested while the engine is idle, so its
  // engine events arrive stamped with this id once the run phase is already
  // back to `NoRun`; routing them needs the retained id.
  last_run_id : String?
  // Workflows this conversation's snippets announced, one row per subagent.
  // Live-only, like the lanes: the run's journal and the children's own
  // transcripts in the store are the record, and a reload rebuilds nothing
  // here until the next bracket or entry arrives.
  workflows : Array[@workflow.Run]
  // Where this conversation's compaction stands; see `CompactionPhase`.
  compaction : CompactionPhase
  // A run finished while this conversation was off screen and the user has
  // not looked since: the sidebar's running pulse settles into a solid dot
  // (accent for success, warn otherwise) until the conversation is opened.
  unseen_finish : Bool
  // When this page saw the current run begin, for the composer row's elapsed
  // span. `None` whenever that moment is not this page's to know — a run
  // adopted from a reconnect started before we were watching, and guessing
  // from the moment we noticed would report a wrong, always-too-short age.
  run_started_ms : Double?
  // The git branch checked out in the workspace, reported by the host's
  // `workspace_branch` op — display only (composer chip). `None` until a probe
  // answers (or when it fails); `Some("")` when the workspace is not a
  // repository. Either way the chip hides. Refreshed when a run starts, a
  // stored session opens, and a run finishes.
  branch : String?
  // How much uncommitted work sits on that branch, answered by the same probe
  // and shown beside it. `None` whenever `branch` is.
  diffstat : DiffStat?
  // Which base the probe that produced that diffstat was told to measure from,
  // echoed back by the reply. Compared against the base a pull request later
  // reports, it is how a diffstat measured from the host's guess — or from a
  // base the pull request has since been retargeted away from — is noticed and
  // measured again. Not `DiffStat::base`: that is the ref the host resolved the
  // hint to, so comparing the two would never agree and would probe forever.
  diffstat_hint : String?
  // The newest branch probe. Replies carry it, so one that is still counting
  // untracked files cannot land on top of a later probe's answer — a run's
  // start and its finish each issue one, and so does opening the popover.
  branch_generation : Int
  // What GitHub says about that branch; see `PullRequestProbe`. `None` until
  // the first lookup is issued.
  pull_request : PullRequestProbe?
  // The newest pull-request lookup, counted the same way and for the same
  // reason. It sits out here rather than in the probe because clearing the
  // probe must not rewind it — see `Conversation::forget_pull_request`.
  pull_request_generation : Int
  // Everything belonging to the turn in flight; see `RunState`.
  turn : RunState
  // Follow-ups submitted into an open run and not yet acknowledged. Queue
  // additions leave when the Desktop host accepts the in-memory mutation;
  // steers leave on their exact id-bearing receipt, or with the run they
  // belong to. Canonical User text never claims ownership, so identical
  // steers from multiple clients cannot collide.
  pending_steers : Array[PendingSteer]
  // Prompts waiting in the Desktop engine process to become later turns.
  // They are transient controller state and never part of the transcript.
  queued_inputs : Array[QueuedInput]
  // The queued prompt currently loaded into the main composer for editing.
  queue_edit_id : String?
  // The permission question this conversation's engine is blocked on, if any.
  //
  // A field rather than a queue because the engine can only be blocked on one
  // at a time: the tool that asks is not `concurrent_safe`, so no second tool
  // is running beside it to ask a second question. If that ever changes, this
  // becomes a queue and the composer has to decide what showing two at once
  // means.
  pending_approval : PendingApproval?
  // The one prompt in flight: submitted, no answer yet. There is at most one
  // — Send is refused while a run is open — so this is a field, not a queue.
  //
  // It exists for a single outcome: a definite refusal, which returns the
  // draft to the composer with its mention chips intact. Every other ending
  // just clears it. It deliberately outlives `run: Starting(..)`, because a
  // competing run replaces that phase and the refusal that competition causes
  // arrives after it.
  pending_prompt : PendingPrompt?
  // The durable transcript: exactly what `session.load` snapshots and
  // `session.event` commits said, nothing else — this is also everything the
  // transcript shows. Every failure the record will never carry is reported
  // to the user directly instead, so no client-local row has to be placed in
  // a chronology it does not belong to. Copy-on-write.
  messages : Array[@transcript.TranscriptItem]
  // The highest durable sequence `messages` reflects: commits at or below it
  // are already applied, `watermark + 1` applies next, and anything later is
  // a gap — this client missed a broadcast — answered by a reload.
  watermark : Int
  // Where the durable transcript stands relative to the store; see
  // `TranscriptSync`.
  sync : TranscriptSync
  // The standing goal mirrored from the durable record's `[goal]` markers:
  // seeded by each snapshot's reduction and folded forward by marker
  // commits in `apply_commit`. Nothing local writes it — goal mode only
  // sends `agent.goal`, and the engine's durable append is what lands here,
  // so the row never claims a goal that was not persisted.
  goal : @transcript.GoalStanding?
  // The goal this conversation is composing, while `/goal` (or the row's
  // Edit) holds its composer. Per-conversation because goal mode survives a
  // switch — the composer hides it rather than discarding it — so a single
  // model-wide slot would let opening goal mode anywhere destroy the draft
  // waiting somewhere else.
  goal_edit : GoalEdit?
  // A goal command sent but not yet durably confirmed. `agent.goal` returns
  // once the command reaches the engine's stdin, which is not persistence:
  // the engine's own append can still fail, or the process can die with the
  // command queued, and then no `[goal]` marker ever commits.
  //
  // Holding the request until the record says so does two things. A set
  // keeps the user's writing recoverable across that window, and either kind
  // takes the row's Edit and ✕ away while it is in flight — a second command
  // sent over the first only earns the host's `GoalPending` refusal.
  //
  // Any durable observation that already shows what was asked for settles it
  // — a marker commit through `apply_commit`, a recovery snapshot through
  // `adopt_snapshot`; see `GoalRequest::settled_by`. Only a definite host
  // refusal retires it unsatisfied, handing a set's text back; a transport
  // failure leaves it standing, because the command may have landed anyway.
  goal_pending : GoalCommand?
} derive(Eq)

///|
/// One goal command in flight: what it asks the record to say, and which
/// send it was.
///
/// The id exists because `GoalRequest` alone is not an identity. The row
/// keeps its actions while a command is out, so the same text — or Clear —
/// can be sent twice, and two such sends are equal values. A late reply to
/// the first would then retire the second, leaving its marker with nothing
/// waiting for it. The id never goes on the wire: it identifies this
/// client's own send to this client's own reply handler, which is the only
/// place the question arises.
priv struct GoalCommand {
  id : String
  request : GoalRequest
  // The durable frontier when this was sent. Its marker can only commit
  // above it, which is what separates "the record just did this" from "the
  // record already said this before I asked" — the two are indistinguishable
  // by state when a set re-asserts an unchanged goal, or a clear lands on an
  // already-goalless session.
  since : Int
} derive(Eq)

///|
/// A goal command in flight, named by the durable state it asks for.
priv enum GoalRequest {
  // The text this set asks to be standing.
  Setting(String)
  Clearing
} derive(Eq)

///|
/// Whether these durable markers contain this request's own result.
///
/// The request is *not* matched against whose command produced the marker.
/// The durable record has no provenance — a `[goal]` commit proves the engine
/// is appending, never that *this* client is the one it appended for, and a
/// retry or a second client can write markers this session never sent. Asking
/// "did the record just do what I asked" is answerable from any durable read;
/// asking "was that echo mine" is not.
///
/// It has to be *did*, not *agrees with*. Re-sending an unchanged goal is a
/// real command, not a no-op: serve records a fresh baseline beside every set
/// marker and restarts the goal cadence from it, and it explicitly keeps two
/// same-text goals apart while they queue. A clear is the same trap in
/// sharper form, since an absence is also what a record carries before any
/// goal exists. So the reduced state is no evidence at all, and the marker is
/// the whole of it: one of this request's own shape, committed above the
/// frontier the request was sent from.
///
/// Nothing is asked of what stands *now*. A set can be blocked, or replaced,
/// before this is ever read — by the agent, or by another client — and none
/// of that unmakes the fact that the set was recorded. "Did my command land"
/// and "what is the goal today" are two questions; the row answers the second
/// from the mirror.
///
/// A commit carries its one marker; a snapshot carries every marker it read.
/// Same question either way, which is why a reload can settle a send whose
/// reply was lost — and why a reload that finds only older markers settles
/// nothing, because there the record genuinely has not answered yet.
fn GoalRequest::settled_by(
  self : GoalRequest,
  since : Int,
  markers : Array[(Int, @transcript.GoalMarker)],
) -> Bool {
  for entry in markers {
    let (sequence, marker) = entry
    if sequence > since &&
      (match (self, marker) {
        (Setting(text), GoalSet(recorded)) => recorded == text
        (Clearing, GoalCleared) => true
        _ => false
      }) {
      return true
    }
  }
  false
}

///|
/// One follow-up submitted into an open run. A queued follow-up waits for its
/// host reply; a steer waits for its id-bearing receipt. The globally unique
/// `submission_id` is the only ownership proof. The original draft shape is
/// retained so a definitive refusal can restore it to the composer without
/// exposing the serialized mention envelope.
priv struct PendingSteer {
  submission_id : String
  // The run this steer was sent into. A receipt names it too, which is what
  // stops a late echo from settling an entry belonging to a newer run.
  run_id : String?
  content : String
  draft : String
  mentions : Array[Mention]
  // The action this particular submission took. The setting may change while
  // it is in flight, so presentation cannot be derived from the current
  // global default.
  behavior : FollowupBehavior
} derive(Eq)

///|
/// One prompt waiting in the Desktop engine's in-memory follow-up queue.
priv struct QueuedInput {
  id : String
  content : String
} derive(Eq)

///|
/// A permission question the engine announced and is blocked on. `detail` is
/// the permission, `body` the program it would be spent on; both are shown
/// verbatim, since a client that paraphrases a permission can get it wrong.
///
/// `run_id` is the run this question belongs to. It rides the answer so a
/// decision the user takes a while over cannot settle a question in a later
/// run that happens to reuse the id sequence.
priv struct PendingApproval {
  /// The id the decision carries back. Reused verbatim across a replay: a
  /// rejoining page answers the same question, not a new one.
  id : String
  run_id : String?
  tool_name : String
  detail : String
  /// What would actually run, verbatim. The card shows it: `detail` names the
  /// permission, and a permission with its subject off screen is not something
  /// anyone can decide on.
  body : String?
  // Set once the answer has been handed to the host, so a second click cannot
  // send a second decision for the same question. The card stays on screen
  // until the engine's `approval_resolved` retires it, because until then the
  // answer has not demonstrably arrived.
  answered : Bool
} derive(Eq)

///|
/// The prompt half of the same idea, minus the queue: see
/// `Conversation::pending_prompt`.
priv struct PendingPrompt {
  submission_id : String
  draft : String
  mentions : Array[Mention]
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
  ts : Double?
  item : @protocol.SessionItem
} derive(Eq)

///|
/// What the main area shows: the active conversation, the Skills page, the
/// Settings page, or one workspace's settings page. Selecting a conversation
/// (or rotating to a new one) always returns to the chat. While the
/// configured endpoint is unusable the chat stays reachable, the API-setup
/// modal takes over until dismissed, and the composer keeps Send disabled.
/// `WorkspaceSettings` carries the project it is about; detaching that
/// project falls back to the chat.
priv enum Screen {
  Chat
  Codex
  Skills
  Settings
  WorkspaceSettings(channel~ : @interop.ChannelId, workspace~ : @common.Uri)
} derive(Eq)

///|
/// One accepted mention, shown as a chip above the composer and folded into
/// the outgoing prompt's `<user_mentions>` envelope on send. `ref` is the
/// envelope form itself (`$` skill, `#` symbol, or an editor comment) — the
/// single source for the chip's glyph/label/jump target (`mention_chip`) and
/// for dedup. `range` keeps the full resolved range the envelope's
/// `file:line` cannot carry, so a draft chip's jump still selects the exact
/// span (`None` for a skill or an unplaced symbol).
type Mention = @composer.Mention

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
/// The latest identity-bearing storage fact this connection observed for one
/// conversation. Deletion is distinct from both lists: encoding all three
/// states prevents a stale unversioned reply from resurrecting a deleted row.
/// A later Started carrying the exact durable store is the creation fact that
/// can supersede deletion without waiting for a reconnect.
priv enum ArchiveDisposition {
  ArchiveLive
  ArchiveStored
  ArchiveDeleted
} derive(Eq)

///|
/// One durable archive identity. Session ids may repeat across project
/// stores, so archive actions, notifications, and tombstones always retain
/// the host-listed workspace beside the id.
priv struct ArchiveRecordKey {
  session : String
  workspace : @common.Uri
} derive(Eq)

///|
fn ArchiveRecordKey::matches(
  self : ArchiveRecordKey,
  item : @transcript.SessionListItem,
) -> Bool {
  item.id == self.session && item.workspace == self.workspace
}

///|
/// Bind a host protocol workspace path to the channel that produced it. A
/// blank or malformed path invalidates the notification: every durable
/// record belongs to a workspace store, so a key without one names nothing.
fn ArchiveRecordKey::from_protocol(
  channel : @interop.ChannelId,
  session : String,
  workspace : String,
) -> ArchiveRecordKey? {
  guard @resource.of_path(channel, workspace) is Some(resource) else {
    return None
  }
  Some({ session, workspace: resource, })
}

///|
/// Encode the selected store for a request only when its resource belongs to
/// the channel that produced it.
fn ArchiveRecordKey::workspace_payload(
  self : ArchiveRecordKey,
  channel : @interop.ChannelId,
) -> String? {
  if @resource.belongs_to(self.workspace, channel) {
    Some(self.workspace.path)
  } else {
    None
  }
}

///|
/// Whole-list replies do not carry a revision and can predate a notification,
/// so they are reconciled through this override until the next connection
/// boundary starts a fresh authoritative list round.
priv struct ArchiveOverride {
  key : ArchiveRecordKey
  disposition : ArchiveDisposition
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
  // Page-unique identity of this remote device connection lifecycle. A
  // removed device may later return with the same relay id; delayed socket
  // callbacks and reconnect timers carry the old value and are ignored.
  // The desktop's non-WebSocket Local channel always uses 0.
  websocket_epoch : Int
  // Advances when reconnect backoff expires. The terminal component observes
  // this transport input and opens exactly one socket for each attempt.
  reconnect_attempt : Int
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
  projects_request_generation : Int
  worktrees_request_generation : Int
  workspace_settings_request_generation : Int
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
  // Registered project directories: the host registry's absolute paths in
  // registration order. The sidebar shows one section per entry.
  projects : Array[@common.Uri]
  // Each project's worktree registry rows, refreshed with the project list
  // and replaced wholesale by `worktree.changed`. The sidebar's name
  // chips read them.
  worktrees : Array[ProjectWorktrees]
  // Each project's desktop-owned settings mirror
  // (`<workspace>/.openseek/settings.json`), fetched with the project list
  // and replaced wholesale by `workspace.settings_changed`. New
  // conversations copy their launch mode from here; an absent row that has
  // not been fetched yet is the Local default.
  workspace_settings : Array[ProjectSettings]
  // The project the user last selected — where "New chat" lands. `None`
  // means nothing has been selected on this device yet, not that a chat has
  // nowhere to go: see `target_project`. A placement always retains its
  // validated absolute-path provenance.
  active_project : @common.Uri?
} derive(Eq)

///|
fn empty_device_state(channel : @interop.ChannelId) -> DeviceState {
  {
    channel,
    bridge: Connecting,
    websocket_epoch: 0,
    reconnect_attempt: 0,
    reconnect_failures: 0,
    connection_generation: 0,
    sessions_request_generation: 0,
    archived_request_generation: 0,
    projects_request_generation: 0,
    worktrees_request_generation: 0,
    workspace_settings_request_generation: 0,
    sessions: [],
    archived: [],
    archive_overrides: [],
    projects: [],
    worktrees: [],
    workspace_settings: [],
    active_project: None,
  }
}

///|
/// The owner key plus the archive-fact cursor at which its component entry
/// was created. A reused session id can therefore name a new entry without
/// intercepting commands that were already queued by the archived entry.
type ComposerActionIdentity = @composer.Identity

///|
/// The one custom select menu currently open in the desktop. Explicit
/// variants keep mutually exclusive menus deterministic across composer,
/// app-settings, and workspace-settings views.
priv enum SelectMenu {
  OpenSeekModelMenu
  OpenSeekReasoningMenu
  CodexModelMenu
  CodexReasoningMenu
  ApiProviderMenu
  FollowupBehaviorMenu
  ThemeMenu
  FontMenu
  FontSizeMenu
  NotificationCornerMenu
  TreeLayoutMenu
  ProjectMenu
} derive(Eq)

///|
/// The exact OpenSeek row the user selected. This is application navigation
/// state, independent of the Sidebar's rendering identity.
priv struct ConversationSelection {
  channel : @interop.ChannelId
  session : String
  workspace : @common.Uri
  record : ConversationRecord
} derive(Eq)

///|
fn ConversationSelection::matches_id(
  self : ConversationSelection,
  id : @conversation.Id,
) -> Bool {
  let record_matches = match (self.record, id.source()) {
    (LiveRecord, @conversation.OpenSeekLive)
    | (ArchivedRecord, @conversation.OpenSeekArchived) => true
    _ => false
  }
  record_matches &&
  self.channel.uri_authority() == id.channel() &&
  self.session == id.conversation() &&
  id.root() == Some(self.workspace.path)
}

///|
fn ConversationSelection::matches_record(
  self : ConversationSelection,
  channel : @interop.ChannelId,
  session : String,
  workspace : @common.Uri,
  record : ConversationRecord,
) -> Bool {
  self.channel == channel &&
  self.session == session &&
  self.workspace == workspace &&
  self.record == record
}

///|
/// A blocking first-load failure belongs to the row the user selected, not
/// to the last conversation whose transcript happened to load successfully.
priv struct ConversationLoadFailure {
  target : ConversationSelection
  message : String
} derive(Eq)

///|
priv struct Model {
  // Connected device channels in stable order: the desktop window's one
  // Local host, or a browser console's roster devices — empty there until
  // the roster loads (`apply_roster`).
  devices : Array[DeviceState]
  // Last WebSocket lifecycle identity issued by this page. It deliberately
  // survives sign-out, so re-adding the same relay device cannot collide with
  // a reconnect timer queued by its retired connection.
  websocket_epoch : Int
  // The device channel selected by in-app navigation — this is not DOM or
  // window focus. Settings/Skills, the composer, and the active conversation
  // all target it. The desktop window is born with `Local`; a browser console
  // stays on an inert `Local` default until the roster verifies and connects
  // the device required by its `?device=` query.
  focused : @interop.ChannelId
  // The tier a new conversation is born with: whatever was last picked in
  // the composer, persisted page-locally. The model a turn actually runs
  // with is the conversation's own `engine_model`, never this.
  default_model : EngineModel
  // The agent a new conversation is born with: whichever provider group the
  // unified model chip was last picked from, persisted page-locally. An
  // existing conversation never reads this — its agent is fixed at creation.
  default_agent : AgentChoice
  // Each conversation's pinned tier, newest first and capped at
  // `ConversationModelsLimit`. A conversation is pinned when the chip gives
  // it a tier and when a run makes it durable — an inherited tier that was
  // actually used counts, or the conversation would come back on whatever
  // default an unrelated chat has moved to since. Reopening recovers from
  // here; `default_model` is only for conversations this list has never held.
  conversation_models : Array[StoredConversationModel]
  // The DeepSeek (and non-GLM custom-model) reasoning choice sent on the next
  // OpenSeek operation. GLM keeps a separate preference below because its
  // forced-thinking low mode is the useful default for ordinary tasks.
  openseek_reasoning : OpenSeekReasoning
  glm_reasoning : OpenSeekReasoning
  max_steps : String
  // Whether the host has a key stored for each keyed provider. The key text
  // itself never reaches a client — the Settings page only needs presence
  // (placeholder wording, the ready gate); a new key is staged in
  // `setup_api_key` until saved through `settings.set`.
  deepseek_key_saved : Bool
  glm_key_saved : Bool
  custom_key_saved : Bool
  setup_api_key : String
  // Which endpoint the engine talks to; `custom_api_url` only matters when
  // the provider is `Custom`. Both mirror the host's settings store and are
  // edited through `settings.set`.
  api_provider : ApiProvider
  custom_api_url : String
  followup_behavior : FollowupBehavior
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
  // Whether the API-setup modal is up. Every settled settings snapshot
  // decides it through `settle_api_setup` — the one place that opens it —
  // and it closes the moment a usable endpoint arrives.
  api_setup_open : Bool
  // The user answered "Not now" to the setup modal. Held until a usable
  // endpoint re-arms the announcement, and deliberately not part of the
  // host-settings mirror: a reconnect or focus switch clears the mirror but
  // must not turn a dismissal back into a fresh popup. Session-local — the
  // next cold start without a key prompts again.
  api_setup_dismissed : Bool
  // Whether this page is the desktop window (the proton webview) rather than
  // a browser reached through a relay. Probed once at startup. Gates the
  // self-update flow: applying an update swaps the
  // bundle under the desktop process and relaunches through the window's
  // close path — from a browser tab, `window.close()` exits nothing, and the
  // update would yank the app out from under whoever is at the machine.
  is_desktop : Bool
  // Whether the native window is currently focused. Conversation navigation
  // has its own `focused` channel; both facts, together with `screen`, decide
  // whether a completed turn was actually visible to the reader.
  window_focused : Bool
  // Installed package version supplied by the native host's `app.info` op.
  app_version : String
  // A browser page's account layer: the relay session and the device
  // roster (see `ConsoleState`). None in the desktop window, whose one
  // Local channel needs no account and no roster.
  console : ConsoleState?
  // The latest host preference is retained even while a fixed theme is
  // selected, so switching Settings back to System applies the current value.
  system_dark : Bool
  // The Settings selection. Its effective palette drives the app root,
  // embedded viewer, and terminal together.
  theme : Theme
  // The Settings selection shared by code content, editor text, and terminals.
  app_font : AppFont
  // The Settings type scale shared by app chrome, editor text, and terminals.
  app_font_size : AppFontSize
  fps_overlay_enabled : Bool
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
  // Right-panel visibility is shared by the shell grid, file-editor lifecycle,
  // and native Browser geometry, so the application root is its single owner.
  // The right-panel component receives these values as read-only input.
  right_panel_open : Bool
  right_panel_menu_open : Bool
  right_panel_expanded : Bool
  // Terminal tabs and their connection snapshots affect both the component
  // view and root layout. The root owns the opaque state once so neither side
  // reports a second visibility copy back to the other.
  terminal : @terminal.State
  // The archive-discard confirmation, staged when the host refused an
  // archive because the conversation's worktree holds uncommitted changes;
  // confirming retries the archive with force.
  archive_confirm : ArchiveConfirm?
  // Permanent archived-chat deletion has its own explicit confirmation. It
  // never shares the worktree-discard dialog because the data at risk differs.
  archived_delete_confirm : ArchivedDeleteConfirm?
  // Controlled sidebar editor for one live conversation title.
  conversation_rename : ConversationRename?
  // Immediate sidebar intent. The loaded `active_session` remains separate so
  // an older async snapshot cannot steal highlight or expose stale content.
  selected_conversation : ConversationSelection?
  conversation_load_failure : ConversationLoadFailure?
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
  // A page-lifetime namespace lets independent monotonic counters become
  // globally unique identities without making `update` read randomness.
  // Different windows get independent timestamp/random namespaces; replaying
  // the same model remains deterministic.
  page_namespace : String
  submission_sequence : Int
  // Every conversation with live client state this app run: the active one,
  // those still running in the background, and those visited and kept for an
  // instant switch back. Copy-on-write, like the transcript arrays.
  conversations : Array[Conversation]
  // The in-app folder picker behind "Add a project"; None while closed.
  project_picker : @project_picker.State?
  // A confirmed add waiting for its registry snapshot; None otherwise.
  pending_project_adoption : ProjectAdoption?
  screen : Screen
  // Codex app-server has an independent durable thread/turn/item model. Keep
  // its page state beside the screen selector instead of folding it into an
  // OpenSeek Conversation, whose persistence and event protocol are different.
  codex : @codex.State
  // The Skills page's own state — the registry catalog, the search filter,
  // in-flight actions, the last failure — which only that page can see.
  skills : @skills.State
  // The focused host's skills library. Root-owned rather than page-owned
  // because the composer's `$` completion reads the same list, which is why
  // it refreshes on connect instead of when the Skills page opens.
  installed_skills : Array[@skills.InstalledItem]
  // Advances only when navigation changes which composer is visible. Local
  // component entries use it to dismiss an old completion menu while keeping
  // each conversation's unsent draft; textarea edits never touch this field or
  // any other part of the root Model.
  composer_context_generation : Int
  // Transient presentation for the visible select or project menu. It closes
  // on context changes, selection, and click-away dismissal.
  select_menu : SelectMenu?
  // Search text inside the default page's registered-project menu. This stays
  // beside `select_menu` so the shell can hide native Browser views beneath
  // the complete top-layer surface.
  project_menu_query : String
  // Every newly observed archive appends its exact owner. The composer consumes
  // this page-lifetime log in order, so a background session cannot regain an
  // old component-local draft when the same session id is later unarchived.
  composer_entry_retirements : Array[@interop.ConversationKey]
  // Cmd/Ctrl+P/T unified Quick Open in the native window and browser console.
  // It is global UI for the focused conversation, not durable conversation
  // state. Owned by the `quick_open` package: this shell only opens it, fences
  // it against conversation changes, and opens the row it accepts.
  quick_open : @quick_open.State
  // Every git probe's request number, minted here rather than per conversation
  // because a conversation archived and reopened is a *new* record, so a
  // counter living on it restarts at zero and hands the old checkout's
  // outstanding replies a number the new one accepts. Kept whole while the
  // frontend runs, it can only ever be spent.
  git_request_generation : Int
  // Whether the composer's git chip has its details popover open. Global UI
  // for the focused conversation like `quick_open`, not conversation state:
  // only one composer is on screen, and a popover left open across a switch
  // would describe the wrong checkout — which `update` fences, since a
  // keyboard switch produces no click for the dismissal listener to see.
  git_details_open : Bool
  // The right panel's dock: the mixed tab strip's membership, order, active
  // tab, and per-conversation parked strips. Owned by the `dock` package;
  // the projection (open files, active file, panel visibility) feeds
  // `file_ctx` every dispatch.
  dock : @dock.State
  // The file subsystem behind the dock's file tabs: the active
  // conversation's file tree and the document table the embedded viewer
  // shows from. Rooted at `conversation_root`; rebuilt when the active
  // conversation changes workspace variant or concrete root. Owned by the
  // `fileeditor` package; this model only carries its state and routes
  // `FileEditor` messages to it.
  file_panel : @fileeditor.State
  // The browser subsystem behind the dock's Browser tabs: per-page address
  // state, keyed by page-global ids that only grow. The pages themselves
  // are native web contents views the desktop host owns.
  preview : @preview.State
  // What the host has been told about the active page's native view: which
  // view is visible, at which bounds, and the geometry signature the last
  // measurement was requested for (see `sync_browser_view`).
  browser_pane : BrowserPane
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
  // "confirming" cannot overlap. The channel is always production: the
  // update manifest lives on the SeekMoon origin and no longer derives
  // from the chat provider.
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
/// The host-side presentation of the active Browser tab's native view, as
/// last commanded: `shown`/`rect` echo the `browser.set_visible`/
/// `browser.set_bounds` already sent, and `geo` is the model-geometry
/// signature the last pane measurement was requested under — the damping
/// that keeps the per-dispatch sync pass from measuring forever.
priv struct BrowserPane {
  shown : Int?
  rect : @preview.Rect?
  geo : BrowserGeometry?
} derive(Eq)

///|
/// Every model-driven input of the browser pane's placement. When any of
/// these change while a view should be on screen, the pane is re-measured;
/// sizes that change without the model (window resize, the width drag) are
/// caught by the pane element's ResizeObserver instead.
priv struct BrowserGeometry {
  // Which view should be visible (`desired_browser_view`), or none.
  desired : Int?
  sidebar_open : Bool
  narrow : Bool
  terminal_open : Bool
  right_panel_expanded : Bool
  tree_layout : @fileeditor.TreeLayout
} derive(Eq)

///|
/// A conversation's open goal edit. It carries no identity of its own: the
/// conversation holding it is the conversation being edited, which is what
/// keeps two open edits from overwriting each other. The draft starts as the
/// mirrored standing goal (editing in place) or empty.
priv struct GoalEdit {
  draft : String
} derive(Eq)

///|
/// Set when the picker's confirm sends `workspace.add`, then settled in two
/// phases because focusing needs two facts that arrive on two channels in
/// either order. The add's own reply is the causal answer to *which*
/// registry row is ours (realpath can respell the picked directory): it
/// fills `resolved`. The fenced registry snapshots own the sidebar list, so
/// the focus itself — activate, fresh chat, scroll into view — waits until
/// a snapshot actually contains the resolved row.
priv struct ProjectAdoption {
  channel : @interop.ChannelId
  // The exact host path sent to `workspace.add`, used to pair its causal
  // reply without routing through URI canonicalization.
  requested : String
  // Frontend identity for matching the canonical registry snapshot.
  picked : @common.Uri
  known : Array[@common.Uri]
  resolved : @common.Uri?
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
  has_glm_key : Bool
  has_custom_key : Bool
  followup_behavior : String
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
  SettingsLoaded(
    notification_corner~ : String,
    tree_layout~ : String,
    theme~ : String,
    font~ : String,
    font_size~ : String,
    fps_overlay_enabled~ : Bool,
    model~ : String,
    conversation_models~ : String,
    agent~ : String,
    codex_model~ : String,
    codex_effort~ : String,
    openseek_effort~ : String,
    glm_effort~ : String
  )
  // The legacy localStorage engine settings, read at bridge time. The
  // desktop window migrates them up to the host once; a browser page only
  // purges them (a stale secret in shared storage is the leak this design
  // removes).
  LegacySettingsRead(
    provider~ : String,
    custom_url~ : String,
    api_key~ : String,
    custom_api_key~ : String
  )
  // Deliberate actions emitted by the component-local input composer. Raw
  // keystrokes never enter this root message loop.
  ComposerAction(@composer.Action)
  // Codex renders a second instance of the same composer component. Keep its
  // action route distinct so an identical thread/session-shaped id can never
  // be mistaken for an OpenSeek conversation owned by the root store.
  CodexComposerAction(@composer.Action)
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
  // Open unified Quick Open in the requested provider in either shell. The
  // shortcut is the shell's because its capture-phase listener owns every
  // application chord; whether the palette may open at all is a shell question
  // too, since a competing modal or a lost bridge already owns the screen.
  QuickOpenOpen(@quick_open.Provider)
  // Everything the open palette does to itself.
  QuickOpen(@quick_open.Msg)
  // Every custom select shares one popup state. A toggle can switch directly
  // between controls; dismissal is separate and idempotent so a click can
  // close the menu and continue to its original target.
  ToggleSelectMenu(SelectMenu)
  CloseSelectMenu
  ProjectMenuQueryChanged(String)
  ProjectMenuProjectChosen(@common.Uri)
  // A pick in the unified model chip, as a `ModelChoice` wire value. Within
  // the visible conversation's own agent it selects that conversation's
  // model; on a composing conversation a cross-agent pick hands the fresh
  // chat to the other agent instead. Either way the pick becomes the default
  // agent and model for new conversations.
  ModelPicked(String)
  // The Codex-only reasoning chip applies to the next ordinary turn. It is a
  // separate setting because the catalog exposes model and effort as two
  // independent fields.
  CodexEffortPicked(String)
  // OpenSeek's fixed `no`/`high`/`max` choice. It shares the composer control
  // with Codex but remains a separate typed value at the request boundary.
  OpenSeekEffortPicked(String)
  MaxStepsChanged(String)
  SetupApiKeyChanged(String)
  ProviderChanged(String)
  FollowupBehaviorChanged(String)
  CustomApiUrlChanged(String)
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
  // Proton package metadata returned by the native host.
  AppInfoLoaded(String)
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
  // The actor-owned download reports throttled byte progress independently
  // of the short request that accepted it.
  UpdateDownloadProgress(downloaded_bytes~ : Int, total_bytes~ : Int?)
  // The host's `update.downloaded` event says the bundle is staged and verified.
  UpdateDownloaded
  // The download or the swap failed; back to Available with a toast.
  UpdateFailed(message~ : String)
  // The host swapped the bundle; close the window so `main` can relaunch.
  UpdateApplied
  OpenSetup
  // The API-setup modal's "Not now" button and its backdrop click.
  DismissApiSetup
  // The composer's BYOK notice reopens the modal a dismissal closed.
  OpenApiSetup
  // Open the app-server-backed Codex page and refresh its authoritative
  // account, model, and thread catalogs.
  OpenCodex
  // The Settings page's "Open config.toml" button: the host ensures and
  // opens the Codex home's configuration with the platform opener. A
  // failure comes back as the toast message below.
  OpenCodexConfig
  CodexConfigOpenFailed(String)
  // The add button creates only a browser-local draft. The generated id owns
  // Files and Terminal until the first prompt creates an app-server thread.
  CodexDraftRotated(cwd~ : String, id~ : String)
  CodexOpenThread(String)
  CodexArchiveThread(String)
  CodexUnarchiveThread(String)
  // Codex owns every app-server-local transition; the root only wraps the
  // package message so Rabbita still has one application Msg type.
  // Every async Codex request and host event retains its source device. The
  // root rejects it after focus moves instead of applying it to another host.
  Codex(channel~ : @interop.ChannelId, @codex.Msg)
  ToggleSidebar
  // A Settings selection fixes the page to Light or Dark and persists it.
  ThemeChanged(String)
  FpsOverlayChanged(Bool)
  // A Settings selection changes code/editor/terminal monospace text and persists it.
  FontChanged(String)
  // A Settings selection changes the shared app/editor/terminal type scale.
  FontSizeChanged(String)
  // The window was resized; `width` decides the narrow (phone) layout.
  ViewportResized(width~ : Int)
  // The native window gained or lost OS focus. This is deliberately distinct
  // from the selected device channel stored in `Model.focused`.
  WindowFocusChanged(Bool)
  SaveApiKey
  OpenSkills
  // Everything the Skills page does with itself once it is open.
  Skills(@skills.Msg)
  Send
  Stop
  // The user answered the active conversation's permission question. `allow`
  // grants the one action it asked about; the card stays until the engine's
  // settlement retires it.
  ApprovalAnswered(allow~ : Bool)
  // A decision that never reached the engine: the bridge call failed, or the
  // host had no live engine to hand it to. Restores the card's buttons, since
  // nothing else will — a settlement only follows a decision that arrived, and
  // the question behind it has no deadline. Addressed exactly, so a stale
  // failure cannot unlock a newer question.
  ApprovalAnswerFailed(
    channel~ : @interop.ChannelId,
    session~ : String,
    id~ : String
  )
  NewChat
  // The channel is captured when rotation is requested, so a focus move can
  // fence the delayed id instead of activating it on the newly focused host.
  SessionRotated(@interop.ConversationKey)
  // Open a conversation on one device's explicit channel, selecting that
  // channel first when it differs from the current one.
  OpenSession(@interop.ChannelId, String)
  RetrySelectedConversation
  // Open a conversation on the channel already focused. A transcript link has
  // only a session id to go on — the child session a sub-run tool card names
  // belongs to the same device as the transcript that names it — and the
  // component is built once, before any model exists to read a channel from.
  OpenSessionHere(String)
  // Open a row from the archived index. Its workspace is part of the row's
  // durable placement and selects the archived twin without restoring it.
  OpenArchivedSession(
    @interop.ChannelId,
    session~ : String,
    workspace~ : @common.Uri
  )
  // The user clicked the system notification posted through Proton's
  // notification extension: jump to the conversation that owned that run.
  // The native extension brings the window forward before emitting the click.
  NotificationClicked(run_id~ : String)
  // A host-side action with no conversation of its own (opening a non-text
  // path in the system app, opening an external URL, launching an app) failed:
  // pops an error toast.
  HostActionFailed(String)
  // The export is already durable, but its default system application could
  // not be opened. The saved path remains useful in the transient toast.
  SessionExportOpenFailed(path~ : String)
  // A transcript file link's host lookup failed. Unlike other host actions,
  // this carries the click identity so a slower older failure cannot surface
  // after a newer editor navigation has already taken precedence.
  OpenFileFailed(
    owner~ : @interop.ConversationKey,
    generation~ : Int,
    message~ : String
  )
  // A safe external anchor was clicked in the Proton page. The document-level
  // capture listener emits this for both Rabbita transcript links and the
  // editor hover's foreign DOM; browser pages keep native new-tab behavior.
  ExternalLinkClicked(String)
  // Open the in-app folder picker against one device's host (browsing starts
  // at that host's home directory), selecting its channel first if needed.
  PickProject(@interop.ChannelId)
  // The Cmd/Ctrl+O chord: open the folder picker for the focused device. A
  // no-op while the picker is already open, so a repeat chord cannot yank
  // the listing back to the home directory mid-navigation.
  AddProjectRequested
  // One picker-package message: navigation, a listing reply, a failure, or
  // a confirm/close. The shell intercepts the confirm's picked directory.
  ProjectPicker(@project_picker.Msg)
  // Detach a project from one device: only the registry entry goes
  // away — the directory and the sessions inside it stay, so re-adding
  // restores them.
  RemoveProject(@interop.ChannelId, @common.Uri)
  // Show the per-workspace settings page for one device's project.
  OpenWorkspaceSettings(@interop.ChannelId, @common.Uri)
  // The workspace settings page's launch-mode select. Carries the raw
  // select value ("local" | "worktree"); update decides what it means.
  WorkspaceDefaultModeChosen(@interop.ChannelId, @common.Uri, String)
  // Whether new or repaired worktrees for this workspace populate the
  // top-level submodules initialized in the main checkout.
  WorkspaceSubmodulesChosen(@interop.ChannelId, @common.Uri, String)
  // Hard bound for that submodule checkout, in seconds. Update accepts only
  // the values rendered by the workspace settings select.
  WorkspaceSubmoduleTimeoutChosen(@interop.ChannelId, @common.Uri, String)
  // Start a fresh conversation in a device's project, selecting its explicit
  // channel first if needed. `None` leaves the device's own selection alone.
  NewChatIn(@interop.ChannelId, @common.Uri?)
  // Flip the composer's launch mode for a conversation that has not begun:
  // workspace root, or a fresh host-named worktree (its execution
  // environment, bound 1:1 at creation).
  ToggleWorktreeMode
  // Retry the active workspace's placement list after its first request
  // failed or remained unanswered. The conversation stays blocked until a
  // real list reply or worktree commit broadcast identifies its placement.
  RetryWorktreePlacement
  // Rebuild the active conversation's missing worktree checkout on its
  // surviving branch. The other safe exit is the ordinary ArchiveSession:
  // a bound conversation never migrates into the workspace root.
  RepairWorktree
  // The archive-discard dialog's two exits: retry the archive with force
  // (discarding the worktree's uncommitted changes), or stand down.
  ConfirmArchiveDiscard
  CancelArchiveDiscard
  // Archive a conversation on its device: the host moves its durable
  // record into the store's `archived` twin and the sidebar moves the row
  // under the Archived group.
  ArchiveSession(@interop.ChannelId, String)
  // Restore an archived conversation into its device's live list.
  UnarchiveSession(@interop.ChannelId, String)
  // Stage, confirm, or cancel permanent deletion of an archived conversation.
  // The confirmation's display title comes from the archived record itself.
  DeleteArchivedSession(@interop.ChannelId, ArchiveRecordKey)
  ConfirmDeleteArchivedSession
  CancelDeleteArchivedSession
  ConversationRenameRequested(id~ : @conversation.Id, label~ : String)
  ConversationRenameChanged(id~ : @conversation.Id, value~ : String)
  ConversationRenameSubmitted(@conversation.Id)
  ConversationRenameCancelled(@conversation.Id)
  ConversationRenameSucceeded(@conversation.Id)
  ConversationRenameFailed(id~ : @conversation.Id, message~ : String)
  // The host's dark-mode preference changed. It updates the palette only while
  // no explicit Light/Dark choice has been saved.
  ColorSchemeChanged(Bool)
  // A local path in the transcript was clicked. Files and directories in the
  // conversation checkout stay in the right panel; other existing paths may
  // use the system opener. Each click spends a generation before the
  // asynchronous request, so only the newest click may steer the panel.
  OpenFile(String)
  // Show a transcript file reference in this Desktop's file manager. The menu
  // exposes this only for a local checkout; resolution still stays host-side
  // so relative paths and editor-position suffixes match `OpenFile` exactly.
  RevealFile(String)
  // The host resolved this text file and optional position inside the
  // checkout. Owner and generation fence replies that arrive after a
  // conversation change or a newer transcript file-link click.
  OpenFileAt(
    owner~ : @interop.ConversationKey,
    generation~ : Int,
    path~ : String,
    line~ : Int?,
    column~ : Int?
  )
  // The host proved that this literal checkout-relative path is a directory.
  // Reveal and expand it in the Files tree. The same owner/generation fence as
  // file links applies.
  OpenDirectoryAt(
    owner~ : @interop.ConversationKey,
    generation~ : Int,
    path~ : String
  )
  // Open or close the composer git chip's details popover.
  ToggleGitDetails
  // Clicks away from a transient menu, one per menu. Each is separate from
  // its toggle on purpose: a dismissal must never reopen what it closed.
  CloseGitDetails
  // The right panel renders these root-owned values and reports only user
  // actions. Keeping the transitions here avoids a component mirror and a
  // second message that writes the same visibility back into the root.
  ToggleRightPanel
  ToggleRightPanelMenu
  ToggleRightPanelExpanded
  CloseRightPanelMenu
  // Close every dock tab through its ordinary teardown path, then keep the
  // empty panel open on the New Tab launcher.
  CloseAllTabs
  // The composer's goal-editing mode over the active conversation: open
  // (prefilled with the mirrored standing goal), edit its draft, send a
  // set/clear to the engine, or dismiss. Each acts on the conversation on
  // screen, which is the one that owns the edit. Set and Clear both leave
  // goal mode optimistically; the row only shows a new goal once the durable
  // `[goal]` marker commits.
  OpenGoalEditor
  GoalDraftEdited(String)
  SubmitGoal
  ClearGoal
  CloseGoalEditor
  // The right panel's strip messages (panel toggle, tab activate/close),
  // routed to the `dock` package's pure strip machine; this update then
  // drives the content subsystems from the transition (see the `Dock` arm).
  Dock(@dock.Msg)
  // The browser subsystem's pure messages: address drafts and the host's
  // `browser.event` view events, routed to the `preview` package.
  Preview(@preview.Msg)
  // The dock launcher's rows: open a blank Browser tab, or open the shared
  // Explorer picker on Files, Changes, or Search. Every row closes the `+`
  // menu; all inventories share this one shell transition.
  BrowserTabRequested
  ExplorerRequested(@fileeditor.ExplorerMode)
  // Open the Workflows tab in the right panel.
  WorkflowsRequested
  // The browser toolbar, acting on whatever Browser tab is active — the
  // messages carry no id so a stale click cannot outlive a tab switch.
  BrowserAddressEdited(String)
  BrowserNavigateSubmitted
  BrowserBack
  BrowserForward
  BrowserReload
  BrowserOpenExternal
  // A double-click on non-interactive top chrome asks the native window to
  // maximize, or to restore when it is already maximized.
  AppToggleMaximizedRequested
  // The native Developer menu always inspects the SeekMoon frontend page.
  // Embedded Browser views can receive their own explicit action later.
  AppDeveloperToolsRequested
  AppCloseWindowRequested
  CloseActiveDockTab
  // The browser pane's on-screen rectangle, reported after a render by the
  // measurer or the pane's ResizeObserver; drives view bounds/visibility.
  BrowserPaneMeasured(rect~ : @preview.Rect)
  // The file subsystem's own messages (tree, viewer, diagnostics,
  // comments), normally routed to the `fileeditor` package's update. The root
  // intercepts messages that cross package ownership: comments become
  // composer chips, file/navigation selections update the dock strip, and a
  // `LanguageRequestFailed` uses the app-owned toast rail.
  FileEditor(@fileeditor.Msg)
  // Terminal UI, host notifications, and xterm callbacks share one root-owned
  // state machine.
  Terminal(@terminal.Msg)
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
  // the single authority over which reconnect loops keep running. The epoch
  // rejects a callback queued by an earlier occupant of the same device id.
  ChannelDown(websocket_epoch~ : Int)
  // A scheduled reconnect attempt came due. Dropped harmlessly when the
  // device was removed or re-added in the meantime.
  ReconnectDue(websocket_epoch~ : Int)
  // A file-panel-scoped host push (`fs.changed`, `fs.watch_failed`,
  // `lsp.diagnostics`),
  // stamped with its channel: the panel serves the focused conversation,
  // so a background device's filesystem noise is dropped at the arm.
  FilePanel(@fileeditor.Msg)
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
  InstalledSkillsLoaded(Array[@skills.InstalledItem])
  InstalledSkillsFailed(String)
  // Another client changed this host's library; the focused client re-reads
  // it so the Skills page and `$` completion share the new contents.
  SkillsChanged
  // The steer RPC failed before its outcome was known. Whether the host took
  // it is unknowable here, so the queue entry ends rather than being guessed
  // at.
  SteerUndelivered(
    session~ : String,
    submission_id~ : String,
    text~ : String,
    run_id~ : String
  )
  // The host definitively returned `steered:false`; no canonical User can
  // follow, so the queue entry retires and its draft comes back. The text is
  // not carried: the entry holds the draft to restore, and without an entry
  // this client did not send it and must not put another client's text in
  // this composer.
  SteerRejected(session~ : String, submission_id~ : String, run_id~ : String)
  QueueAccepted(
    session~ : String,
    action~ : @protocol.QueueAction,
    run_id~ : String
  )
  QueueAddRejected(session~ : String, submission_id~ : String, run_id~ : String)
  QueueSteerRejected(
    session~ : String,
    submission_id~ : String,
    run_id~ : String,
    message~ : String
  )
  // The addressed run was already absent when Stop reached the host. This is
  // success for the user's intent, but no future Finished notification can
  // retire a stale local Cancelling phase, so the reply itself must do it.
  CancelNotOpen(run_id~ : String)
  // A cancellation that could not be delivered must put the exact run back
  // into a stoppable phase. A lifecycle resync follows in case the response
  // failed after the run independently ended.
  CancelFailed(run_id~ : String, message~ : String)
  SessionsLoaded(
    Array[@transcript.SessionListItem],
    connection_generation~ : Int,
    request_generation~ : Int
  )
  SessionsFailed(String)
  // The host's identity-bearing `session.changed` broadcast. Archive changes
  // invalidate that exact live target immediately; rename and every placement
  // change re-read both sidebar lists for their durable contents.
  SessionsChanged(
    change~ : String,
    key~ : ArchiveRecordKey,
    fresh_session~ : String?
  )
  SessionLoaded(
    session~ : String,
    items~ : Array[@transcript.TranscriptItem],
    watermark~ : Int,
    goal~ : @transcript.GoalStanding?,
    goal_markers~ : Array[(Int, @transcript.GoalMarker)],
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
    goal~ : @transcript.GoalStanding?,
    goal_markers~ : Array[(Int, @transcript.GoalMarker)],
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
    // The commit's own store stamp, kept on the message so a turn dates
    // itself the moment it lands rather than only after the next reload.
    ts~ : Double?,
    item~ : @protocol.SessionItem,
    // The durable store root the host read this commit from — the store
    // half of the session's identity.
    session_root~ : @common.Uri
  )
  // The host's `subrun.progress` broadcast: a running sub-run advanced. Not
  // durable and not lifecycle — the raw stream's brackets own the sub-run's
  // start and end, and this only refreshes what it is doing in between.
  SubrunProgressed(
    id~ : String,
    session~ : String,
    steps~ : Int,
    activity~ : String
  )
  // The host's `workflow.entry` broadcast: one resolved call of a workflow a
  // snippet is running, read from the run's journal. Routed to the parent
  // conversation by the entry's own session, like sub-run progress.
  WorkflowEntryArrived(@interop.ChannelId, @workflow.Entry)
  // The registered projects — the reply to `workspace.list`. Both
  // generations are required: reconnect rejects a dead socket, while request
  // generation rejects an older reply from the current connection.
  ProjectsLoaded(
    Array[@common.Uri],
    connection_generation~ : Int,
    request_generation~ : Int
  )
  // The host's canonical post-commit registry broadcast. Every client adopts
  // the same list in durable write order and invalidates older list replies.
  ProjectsChanged(Array[@common.Uri])
  // Our own `workspace.add`'s reply: the canonical list right after the
  // commit, produced under the registry lock. `added` echoes the request's
  // directory, pairing the reply with the confirm that sent it — a reply
  // for a superseded confirm must not resolve the current pending. It only
  // resolves identity and never touches the fenced list state; an empty
  // list means the reply could not be read as resources.
  ProjectAddCommitted(added~ : String, paths~ : Array[@common.Uri])
  ProjectFailed(String)
  // One workspace's desktop-owned settings — the reply to
  // `workspace.settings_get`, fenced per workspace like `WorktreesLoaded`.
  // A failed read dispatches nothing and keeps the Local default everywhere.
  WorkspaceSettingsLoaded(
    workspace~ : @common.Uri,
    worktree_mode~ : Bool,
    checkout_submodules~ : Bool,
    submodule_checkout_timeout_seconds~ : Int,
    connection_generation~ : Int,
    request_generation~ : Int
  )
  // The post-commit `workspace.settings_changed` broadcast for one
  // workspace: every client adopts the committed state in write order.
  WorkspaceSettingsChanged(
    workspace~ : @common.Uri,
    worktree_mode~ : Bool,
    checkout_submodules~ : Bool,
    submodule_checkout_timeout_seconds~ : Int
  )
  // A `workspace.settings_set` this client sent failed; the message pops as
  // a toast and the workspace's settings are re-read.
  WorkspaceSettingsSaveFailed(workspace~ : @common.Uri, message~ : String)
  // One workspace's worktree registry — the reply to `worktree.list`, with
  // the same two-generation staleness fence as `ProjectsLoaded`.
  WorktreesLoaded(
    Array[WorktreeRow],
    workspace~ : @common.Uri,
    connection_generation~ : Int,
    request_generation~ : Int
  )
  // A failed list leaves that workspace's placement unresolved. Carry both
  // generations so a dead connection or an older request cannot surface a
  // stale error after a newer snapshot or broadcast has already arrived.
  WorktreesFailed(
    workspace~ : @common.Uri,
    connection_generation~ : Int,
    request_generation~ : Int,
    message~ : String
  )
  // The post-commit `worktree.changed` broadcast for one workspace.
  WorktreesChanged(Array[WorktreeRow], workspace~ : @common.Uri)
  // A `worktree.create` this client asked for succeeded mid-chain: bind
  // the composing conversation to the new environment (the start request
  // follows inside the same command).
  WorktreeCreated(workspace~ : @common.Uri, name~ : String, session~ : String)
  // An archive was refused because the conversation's worktree holds
  // uncommitted changes; the client stages the discard-confirmation dialog.
  ArchiveNeedsForce(
    session~ : String,
    refusal~ : @protocol.ArchiveNeedsForceReply
  )
  // The archived conversations — the reply to `archived_sessions` and to a
  // successful `archive_session`/`unarchive_session` alike.
  ArchivedLoaded(
    Array[@transcript.SessionListItem],
    connection_generation~ : Int,
    request_generation~ : Int,
    fresh_session~ : String
  )
  // The successful delete reply names the identity it removed and a fresh
  // send target, so it can tombstone and leave an active deleted record even
  // when the broadcast arrives later.
  ArchivedDeleted(
    key~ : ArchiveRecordKey,
    sessions~ : Array[String],
    items~ : Array[@transcript.SessionListItem],
    connection_generation~ : Int,
    request_generation~ : Int,
    fresh_session~ : String
  )
  ArchiveFailed(String)
  DeleteArchivedFailed(String)
  // A rebuild of a missing worktree failed. The canonical rows still arrive
  // as `worktree.changed`, so this only reports the refusal.
  WorktreeFailed(String)
  // A `workspace_branch` reply: the git branch of `session`'s workspace —
  // `Some("")` when it is not a repository, `None` when the probe failed or
  // answered unintelligibly — and how much uncommitted work sits on it.
  // `generation` is the probe that asked; an older one's answer is discarded.
  // `base_hint` is the baseline that probe was given, carried back rather than
  // remembered: it says what the diffstat in the same message measures from.
  BranchLoaded(
    session~ : String,
    branch~ : String?,
    diffstat~ : DiffStat?,
    generation~ : Int,
    base_hint~ : String?
  )
  // A `git.pull_request` reply. `generation` is which request this answers,
  // and is what matches it to the probe waiting for it; `branch` is the one
  // that request was issued against, kept for the label when the host reports
  // none; `queried` is the branch the host actually read from `HEAD`, and is
  // what the answer gets labelled with — the checkout can move between the
  // two. A failed lookup arrives here too, with nothing in it, so the
  // conversation never stays wedged waiting for an answer that will not come.
  PullRequestLoaded(
    session~ : String,
    branch~ : String,
    generation~ : Int,
    queried~ : String?,
    pull_request~ : PullRequest?,
    compare_url~ : String?
  )
  // The host accepted a prompt: `session` routes the event to its
  // conversation, and everything after a `started` routes by `run_id`.
  Started(
    run_id~ : String,
    session~ : String,
    model~ : EngineModel,
    max_steps~ : Int,
    session_root~ : @common.Uri?,
    submission_id~ : String?
  )
  // One complete `agent.runs` reply. Replayed starts and the negative-set
  // frontier must be accepted or rejected together at one connection
  // generation; dispatching its rows separately would let a stale reply
  // resurrect a run after a later BridgeReady already resynced it away.
  RunsLoaded(
    runs~ : Array[RecoveredRun],
    settled~ : Array[RecoveredSettlement],
    // Permission questions the host's engines are still blocked on. A card
    // this page rendered before a reload is gone with the page, and nothing
    // in the durable record can bring it back — so a rejoining client is
    // handed the standing question rather than watching a run that never
    // moves.
    approvals~ : Array[RecoveredApproval],
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
  // the same connection; any other status leaves delivery unconfirmed. A
  // reply that returns always names the run it opened.
  StartResponded(
    session~ : String,
    submission_id~ : String,
    run_id~ : String,
    status~ : String,
    exit_code~ : Int
  )
  // The response path failed before host acceptance was knowable. Nothing
  // guesses on the client's behalf: the prompt in flight settles and a reload
  // shows what the record actually holds.
  StartUndelivered(
    session~ : String,
    submission_id~ : String,
    message~ : String
  )
  // The host definitively refused this exact request. Restore its draft and
  // retire the prompt in flight immediately.
  StartRejected(session~ : String, submission_id~ : String, message~ : String)
  // `worktree.create` failed before `agent.start` was sent. Restore the draft
  // like StartRejected, but report this recoverable setup failure as a toast
  // rather than putting an agent-style error in the transcript.
  WorktreeSetupFailed(
    session~ : String,
    submission_id~ : String,
    message~ : String
  )
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
  // The `agent.goal` bridge request was rejected (no engine, host error):
  // no `[goal]` marker will commit, so the failure is reported here. `draft`
  // is the text that never landed — carried back so the composer can return
  // it to the user, the way a rejected prompt restores its own draft. `None`
  // was a clear, which has nothing to restore. `command` names which send
  // this answers, so a late reply cannot retire the one that replaced it.
  GoalRejected(
    session~ : String,
    command~ : String,
    draft~ : String?,
    message~ : String
  )
  // The `agent.goal` call failed on the transport rather than being refused,
  // so whether the host took it is unknown: the socket can drop after the
  // command reached the engine and before the reply came back, and the
  // `[goal]` marker still commits. The request therefore stays in flight —
  // handing the draft back here would say the goal is unset while the record
  // may already carry it, and inviting a resend races the marker. `draft` is
  // reported in the notice so the writing survives even if nothing landed.
  //
  // It names its send like `GoalRejected` does. It retires nothing, but it
  // still makes a claim — that this text's fate is unknown — and that claim
  // goes stale the moment the record settles the send or a newer one
  // replaces it.
  GoalUndelivered(
    session~ : String,
    command~ : String,
    draft~ : String?,
    message~ : String
  )
  // `answer` accompanies normal success and context yield (where it is
  // continuation guidance); other terminal statuses carry none.
  Finished(run_id~ : String, status~ : String, answer~ : String?)
  // A failed command's process reached EOF after lifecycle was already
  // settled. This is only the exact durable boundary, never a second finish.
}

///|
/// A conversation with nothing in it yet, in the project that owns it. The
/// project is required because a conversation is where work happens: it
/// names the store its record lives in and the directory every run, file,
/// and terminal request resolves against. A caller whose session is bound to
/// one of that project's worktrees narrows `workspace` afterwards, once the
/// registry row that proves the binding is in hand.
fn empty_conversation(
  channel : @interop.ChannelId,
  session_id : String,
  project : @common.Uri,
  model? : EngineModel = DsPro,
) -> Conversation {
  {
    device: channel,
    session_id,
    record: LiveRecord,
    workspace: Project(root=project),
    worktree_mode: false,
    engine_model: model,
    task: "",
    mentions: [],
    composer_draft_present: false,
    workflows: [],
    run: NoRun(ended=None),
    last_run_id: None,
    compaction: NotCompacting,
    unseen_finish: false,
    run_started_ms: None,
    branch: None,
    diffstat: None,
    diffstat_hint: None,
    branch_generation: 0,
    pull_request: None,
    pull_request_generation: 0,
    turn: RunState::empty(),
    pending_steers: [],
    queued_inputs: [],
    queue_edit_id: None,
    pending_approval: None,
    pending_prompt: None,
    messages: [],
    watermark: 0,
    sync: Synced,
    goal: None,
    goal_edit: None,
    goal_pending: None,
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
  // A browser console requires `?device=` (minted by the relay's redirect off
  // retired `/d/<id>/` routes) as its page-lifetime device identity. An
  // optional `?workspace=` places that device's first conversation.
  let page_channel = @interop.page_channel()
  let page_device = @interop.page_query_param("device")
  // Capture the browser's exact local path once before the first render.
  // Packaged release pages must return to their versioned bundle after OAuth;
  // reading `window.location` later from `view` would make rendering impure.
  let login_return_to = if @interop.js_prop(@js.globalThis, "location")
    is Some(location) {
    let pathname : String? = @js.Cast::into(
      (location.get_with_string("pathname") : @js.Value),
    )
    let search : String? = @js.Cast::into(
      (location.get_with_string("search") : @js.Value),
    )
    if pathname is Some(pathname) &&
      pathname.has_prefix("/") &&
      !pathname.has_prefix("//") {
      pathname + search.unwrap_or("")
    } else {
      "/console/"
    }
  } else {
    "/console/"
  }
  let preselect_owner = match page_channel {
    Some(channel) => Some(channel)
    None => page_device.map(id => @interop.ChannelId::Remote(id))
  }
  let preselect_project = match
    (@interop.page_query_param("workspace"), preselect_owner) {
    (Some(path), Some(channel)) => @resource.of_path(channel, path)
    _ => None
  }
  let is_desktop = @interop.openseek_api() is Some(_)
  {
    // The desktop window's one channel; a browser page starts empty and
    // fills `devices` from the fetched roster (`apply_roster`).
    devices: match page_channel {
      Some(channel) =>
        [{ ..empty_device_state(channel), active_project: preselect_project, }]
      None => []
    },
    websocket_epoch: 0,
    focused: page_channel.unwrap_or(@interop.ChannelId::Local),
    default_model: DsFlash,
    default_agent: OpenSeekAgent,
    conversation_models: [],
    openseek_reasoning: ReasoningHigh,
    glm_reasoning: ReasoningOff,
    max_steps: DefaultMaxSteps,
    deepseek_key_saved: false,
    glm_key_saved: false,
    custom_key_saved: false,
    setup_api_key: "",
    api_provider: Deepseek,
    custom_api_url: "",
    followup_behavior: FollowupSteer,
    settings_saves: 0,
    host_settings_revision: -1,
    deferred_host_settings: None,
    legacy_cleanup_pending: false,
    is_desktop,
    window_focused: !is_desktop || @interop.page_has_focus(),
    app_version: "development",
    // Every browser page is the console: it signs in against the relay and
    // verifies its required query-selected device before that channel opens.
    console: if is_desktop {
      None
    } else {
      Some(
        empty_console_state(page_device, preselect_project, login_return_to~),
      )
    },
    system_dark: host_prefers_dark(),
    theme: System,
    app_font: SystemMono,
    app_font_size: AppFontSize(14),
    fps_overlay_enabled: false,
    narrow,
    sidebar_open: !narrow,
    right_panel_open: false,
    right_panel_menu_open: false,
    right_panel_expanded: false,
    terminal: @terminal.State::empty(),
    active_session: "",
    loading_conversation: None,
    transcript_request_generation: 0,
    page_namespace: generated_session_id(),
    submission_sequence: 0,
    conversations: [],
    project_picker: None,
    pending_project_adoption: None,
    archive_confirm: None,
    archived_delete_confirm: None,
    conversation_rename: None,
    selected_conversation: None,
    conversation_load_failure: None,
    screen: Chat,
    codex: @codex.State(),
    skills: @skills.State::empty(),
    installed_skills: [],
    composer_context_generation: 0,
    select_menu: None,
    project_menu_query: "",
    composer_entry_retirements: [],
    quick_open: @quick_open.State::empty(),
    git_request_generation: 0,
    git_details_open: false,
    dock: @dock.State::empty(),
    file_panel: @fileeditor.State::empty(),
    preview: @preview.State::empty(),
    browser_pane: { shown: None, rect: None, geo: None, },
    notifications: [],
    notification_seq: 0,
    notification_corner: BottomRight,
    tree_layout: RightSidebar,
    update_ux: UpdateUnknown,
    api_setup_open: false,
    api_setup_dismissed: false,
    remote_access: None,
    remote_connecting: false,
    remote_error: None,
  }
}

///|
/// The state of one connected channel; `None` for a channel this page does
/// not hold — including a browser page's query-selected device before the
/// roster verifies and connects it, or after that target is retired.
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
/// Resolve the channel selected in `focused` to its connected device state.
/// This is application navigation state, not DOM or window focus. `None`
/// means the selected channel is not currently present in `devices`.
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
fn Model::with_active_project(self : Model, project : @common.Uri?) -> Model {
  guard self.focused_device() is Some(dev) else { return self }
  self.replace_device({ ..dev, active_project: project, })
}

///|
/// Where a new conversation lands on this device: the project last selected,
/// or the first registered one when nothing has been selected yet — the
/// state a freshly connected page is in, and the reason the app opens a chat
/// instead of waiting for the user to pick a project first. `None` only when
/// the device has no project at all, which is the onboarding state.
fn DeviceState::target_project(self : DeviceState) -> @common.Uri? {
  match self.active_project {
    Some(project) => Some(project)
    None => self.projects.get(0)
  }
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
  "SeekMoon"
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
/// What the Skills page draws against: the device it acts on, and that
/// device's library as the root mirrors it.
fn Model::skills_input(self : Model) -> @skills.Input {
  { channel: self.focused, installed: self.installed_skills, }
}

///|
/// Whether the focused host has supplied an authoritative settings snapshot
/// for the current bridge generation. A negative revision is the loading
/// sentinel installed on startup, focus changes, and reconnects.
fn Model::host_settings_loaded(self : Model) -> Bool {
  self.host_settings_revision >= 0
}

///|
/// Forget every value owned by the focused host before fetching another
/// snapshot. The neutral values are deliberately not actionable while the
/// revision remains negative; this prevents a failed or delayed `settings.get`
/// from exposing one device's configuration on another device. The setup
/// modal closes with the mirror it was rendering — an open modal over the
/// loading sentinel would show default data with every control disabled —
/// and the next authoritative snapshot reopens it if still warranted.
fn Model::clear_host_settings(self : Model) -> Model {
  {
    ..self,
    api_setup_open: false,
    api_provider: Deepseek,
    custom_api_url: "",
    followup_behavior: FollowupSteer,
    deepseek_key_saved: false,
    glm_key_saved: false,
    custom_key_saved: false,
    setup_api_key: "",
    settings_saves: 0,
    host_settings_revision: -1,
    deferred_host_settings: None,
    legacy_cleanup_pending: false,
  }
}

///|
/// Fold one host settings payload into the mirror. Whether the result is
/// usable — and how loudly to say so when it is not — is the update
/// handlers' call (the API-setup modal, the Settings guide); this fold only
/// mirrors the store, so a payload applied from a deferred flush can never
/// yank the screen around on its own.
fn Model::apply_host_settings(self : Model, settings : HostSettings) -> Model {
  let next = {
    ..self,
    host_settings_revision: settings.revision,
    deferred_host_settings: None,
    api_provider: ApiProvider::parse(settings.provider),
    custom_api_url: settings.custom_api_url,
    followup_behavior: FollowupBehavior::parse(settings.followup_behavior),
    deepseek_key_saved: settings.has_deepseek_key,
    glm_key_saved: settings.has_glm_key,
    custom_key_saved: settings.has_custom_key,
  }
  next.align_fresh_conversation_with_provider()
}

///|
/// Keep a never-started chat aligned with the host endpoint. Stored and
/// already-running conversations remain pinned: changing their model behind
/// the user's back would rewrite conversation semantics, while a fresh chat
/// has no history to preserve and otherwise begins with a known-bad
/// provider/model mismatch.
fn Model::align_fresh_conversation_with_provider(self : Model) -> Model {
  let default_model = if self.default_model.matches_provider(self.api_provider) {
    self.default_model
  } else {
    self.api_provider.default_model()
  }
  let next = { ..self, default_model, }
  guard next.composing_new_chat() &&
    next.active_conversation() is Some(conv) &&
    !conv.engine_model.matches_provider(next.api_provider) else {
    return next
  }
  next.replace_conversation({ ..conv, engine_model: default_model, })
}

///|
/// The reasoning preference for one model family. GLM's `ReasoningOff` wire
/// value is translated by the engine to its lowest supported effort (`low`).
fn Model::reasoning_for(
  self : Model,
  engine_model : EngineModel,
) -> OpenSeekReasoning {
  match engine_model {
    Glm53 | Glm53Flash => self.glm_reasoning
    DsPro | DsFlash | Other(_) => self.openseek_reasoning
  }
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
  { ..self, deferred_host_settings: Some(deferred), }
}

///|
/// Apply the newest deferred status once optimistic writes no longer protect
/// the form. A lower revision is discarded; equal is deliberately accepted
/// so a failed optimistic edit can be restored by an authoritative `get`.
/// The settled mirror then decides the setup modal like any other snapshot —
/// a deferred first snapshot (the legacy migration races it here) must be
/// able to open the modal, not just retire it.
fn Model::flush_host_settings(self : Model) -> Model {
  let next = match self.deferred_host_settings {
    Some(settings) if settings.revision >= self.host_settings_revision =>
      self.apply_host_settings(settings)
    _ => { ..self, deferred_host_settings: None, }
  }
  next.settle_api_setup()
}

///|
/// Whether the composer should carry the BYOK reminder — the durable surface
/// once the setup modal was dismissed, because a greyed Send with no
/// explanation anywhere in the UI is the state the modal exists to prevent.
/// Gated on the loaded mirror so a reconnect's loading sentinel cannot flash
/// it, and shown regardless of the dismissal: quiet must not mean lost.
fn Model::api_setup_banner_visible(self : Model) -> Bool {
  self.bridge_state() is Connected &&
  self.host_settings_loaded() &&
  !self.api_ready()
}

///|
/// The one rule for the API-setup modal, applied whenever the settings
/// mirror settles: a usable endpoint retires the modal and re-arms the
/// announcement for the next break; an explicit "Not now" holds until then;
/// the Settings page stays modal-free (its guide already says what is
/// missing); otherwise an unusable endpoint keeps the modal up — the key is
/// the one thing SeekMoon cannot run without, so a dismissible toast is not
/// loud enough.
fn Model::settle_api_setup(self : Model) -> Model {
  // The loading sentinel's neutral values are not a verdict on the endpoint;
  // a flush with nothing applied (a failed save before any snapshot) must
  // not announce them.
  guard self.host_settings_loaded() else { return self }
  // A menu rendered inside the modal cannot outlive that modal. Preserve a
  // Settings-page menu when no modal is being retired; both surfaces reuse
  // the same select component and global menu identity.
  let select_menu = if self.api_setup_open { None } else { self.select_menu }
  if self.api_ready() {
    { ..self, api_setup_open: false, api_setup_dismissed: false, select_menu, }
  } else if self.api_setup_dismissed || self.screen is Settings {
    { ..self, api_setup_open: false, select_menu, }
  } else {
    { ..self, api_setup_open: true, }
  }
}

///|
/// Whether the configured endpoint is usable as it stands: the official
/// endpoint needs a key stored on the host, and a custom endpoint needs a
/// plausible URL. The credentials themselves live on the host; a start
/// carries none.
fn Model::api_ready(self : Model) -> Bool {
  match self.api_provider {
    Deepseek => self.deepseek_key_saved
    Glm => self.glm_key_saved
    Custom => plausible_endpoint_url(self.custom_api_url)
  }
}

///|
/// Whether a custom endpoint URL is complete enough to try: an http(s)
/// scheme followed by at least one host character. The URL is pushed to the
/// host per keystroke, so a prefix the user is still typing must not read
/// as usable — that would retire the setup modal mid-word and arm Send
/// against an endpoint every run fails on.
fn plausible_endpoint_url(url : String) -> Bool {
  url.trim() =~ re"^https?://[^/]"
}

///|
/// The status implied by the settings alone: whether the configured endpoint
/// is ready to accept a prompt, and what is missing when it is not.
fn Model::settings_status(self : Model) -> Status {
  if self.api_ready() {
    Ready
  } else if self.api_provider is (Deepseek | Glm) {
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
    // Onboarding has no conversation and therefore no run of its own; the
    // settings-derived readiness is the whole of what can be reported.
    Connected =>
      match self.active_conversation().map(conv => conv.run) {
        None | Some(NoRun(ended=None)) => self.settings_status()
        Some(NoRun(ended=Some(RunFailed))) => Failed
        Some(NoRun(ended=Some(RunErrored))) => Errored
        Some(NoRun(ended=Some(RunFinished(outcome)))) => Finished(outcome)
        Some(Starting(..)) => Starting
        Some(Open(stage=Opened, ..)) => Running
        Some(Open(stage=AtStep(step), ..)) => Step(step)
        Some(Open(stage=Cancelling, ..)) => Cancelling
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
    if conv.pending_prompt is Some(pending) {
      initial_ids.push(pending.submission_id)
    }
    {
      session: conv.session_id,
      state,
      initial_ids,
      pending_approval_id: conv.pending_approval.map(pending => pending.id),
    }
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
            conv.has_initial_submission(submission_id) {
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
/// The registered project a session belongs to on `channel`: the sidebar list's
/// grouping when the store knows the session, the live conversation's own
/// placement otherwise (a fresh chat that has not reached the store yet).
/// `None` when this page knows of neither — an id from a store it has not
/// listed, which nothing here can place.
fn Model::session_project(
  self : Model,
  channel : @interop.ChannelId,
  session_id : String,
) -> @common.Uri? {
  let sessions = match self.device_state(channel) {
    Some(dev) => dev.sessions
    None => []
  }
  for item in sessions {
    if item.id == session_id {
      return Some(item.workspace)
    }
  }
  match self.find_conversation(channel, session_id) {
    Some(conv) => Some(conv.project())
    // A sub-run's child (`<parent>-sr-N`) lives in its parent's store by
    // construction, and it is usually NOT listed while it runs: the inventory
    // is refreshed at connect, archive and unarchive, not when a child record
    // appears mid-run. A click on a workflow row must still open it, so it is
    // placed where its parent is; the host reads the record by id, and the
    // sub-run probe keeps it moving on screen.
    None =>
      match @transcript.subrun_parent(session_id) {
        Some(parent) => self.session_project(channel, parent)
        None => None
      }
  }
}

///|
/// Resolve a host-reported durable session root back to a registered project.
/// Project conversations live at `<project>/.openseek`; a root outside every
/// registered project matches nothing here. The lexical helper normalizes
/// Windows separators.
fn DeviceState::project_for_session_root(
  self : DeviceState,
  session_root : @common.Uri?,
) -> @common.Uri? {
  guard session_root is Some(session_root) else { return None }
  for workspace in self.projects {
    if @resource.relative_to(session_root, workspace) ==
      Some(@pathx.Relative(".openseek")) {
      return Some(workspace)
    }
  }
  None
}

///|
/// Classify a broadcast durable store root into its owning project. Every
/// store belongs to one: the registry names it when that mirror has already
/// arrived, and the store layout (`<project>/.openseek`) names it until then,
/// so the classification is correct even while the projects reply is in
/// flight. `None` is a foreign writer with an unexpected layout: nothing
/// here can say where that record lives, so the event carrying it is dropped
/// rather than attached to a guessed directory.
fn DeviceState::placement_for_store_root(
  self : DeviceState,
  root : @common.Uri,
) -> @common.Uri? {
  if self.project_for_session_root(Some(root)) is Some(project) {
    return Some(project)
  }
  if @common.ext_uri.basename(root) == ".openseek" {
    return Some(@common.ext_uri.dirname(root))
  }
  None
}

///|
/// The newest archive disposition this connection observed for one exact
/// store-qualified record.
fn DeviceState::archive_override(
  self : DeviceState,
  key : ArchiveRecordKey,
) -> ArchiveDisposition? {
  for fact in self.archive_overrides {
    if fact.key == key {
      return Some(fact.disposition)
    }
  }
  None
}

///|
/// One channel's archive disposition for `key` — the Model-level view
/// of `DeviceState::archive_override`.
fn Model::archive_override(
  self : Model,
  channel : @interop.ChannelId,
  key : ArchiveRecordKey,
) -> ArchiveDisposition? {
  guard self.device_state(channel) is Some(dev) else { return None }
  dev.archive_override(key)
}

///|
/// Record one archive notification as the sole current override for its
/// record on `channel`. This copy-on-write replacement is what lets every
/// later list or commit handler consult the same monotonic fact.
fn Model::with_archive_override(
  self : Model,
  channel : @interop.ChannelId,
  key : ArchiveRecordKey,
  disposition : ArchiveDisposition,
) -> Model {
  guard self.device_state(channel) is Some(dev) else { return self }
  // Leaving the live state — stored or deleted — makes the composer's cached
  // entry unaddressable, so the transition also records a retirement that
  // expires stale composer actions for this owner.
  let newly_retired = !(disposition is ArchiveLive) &&
    dev.archive_override(key) is (None | Some(ArchiveLive))
  let overrides = dev.archive_overrides.filter(item => item.key != key)
  overrides.push({ key, disposition, })
  let model = self.replace_device({ ..dev, archive_overrides: overrides, })
  if !newly_retired {
    return model
  }
  let composer_entry_retirements = model.composer_entry_retirements.copy()
  composer_entry_retirements.push({ channel, session: key.session, })
  { ..model, composer_entry_retirements, }
}

///|
/// Whether re-reading this conversation can address a durable record. Local
/// a failed pre-persistence start does not prove one exists; using it as a
/// reload gate would turn every reconnect/reselect into three noisy
/// `session.load` failures for an unsaved chat.
fn Model::can_reload_transcript(self : Model, conv : Conversation) -> Bool {
  if conv.is_archived_read_only() ||
    conv.watermark > 0 ||
    !conv.messages.is_empty() ||
    conv.sync is ReloadFailed(..) ||
    // An outstanding command may already have been appended, and re-reading
    // is the only way to find out. Without this a `/goal` on an otherwise
    // empty conversation has nothing else to reload for, so the request
    // would wait for a snapshot that is never asked for.
    conv.awaits_durable_proof() {
    return true
  }
  match self.device_state(conv.device) {
    Some(dev) => dev.sessions.iter().any(item => item.id == conv.session_id)
    None => false
  }
}

///|
/// The tier this conversation was last given, if the page still remembers
/// one. `None` — never chosen, or dropped by the cap — leaves the caller to
/// pick its own fallback: the page default usually, a live run's tier when
/// the conversation is first seen through one.
fn Model::remembered_model(
  self : Model,
  channel : @interop.ChannelId,
  session : String,
) -> EngineModel? {
  let key = conversation_model_key(channel, session)
  for entry in self.conversation_models {
    if entry.key == key {
      return Some(entry.model)
    }
  }
  None
}

///|
/// Remember a conversation's tier, moving it to the front so the cap drops
/// whichever conversation the user has gone longest without choosing for.
fn Model::remember_model(
  self : Model,
  channel : @interop.ChannelId,
  session : String,
  model : EngineModel,
) -> Model {
  {
    ..self,
    conversation_models: remembered_with(
      self.conversation_models,
      conversation_model_key(channel, session),
      model,
    ),
  }
}

///|
/// Move one conversation to the front of a remembered list, dropping the
/// least recently chosen once the cap is reached. Free-standing because the
/// durable store folds the same way: a write merges into the rows already
/// there rather than replacing them (see `save_conversation_model`).
fn remembered_with(
  entries : Array[StoredConversationModel],
  key : String,
  model : EngineModel,
) -> Array[StoredConversationModel] {
  let merged : Array[StoredConversationModel] = [{ key, model, }]
  for entry in entries {
    if entry.key != key && merged.length() < ConversationModelsLimit {
      merged.push(entry)
    }
  }
  merged
}

///|
/// The conversation on screen, when there is one. `None` is the state the app
/// starts in and returns to whenever no project can hold a chat: the registry
/// has not arrived yet, or every project was detached. A conversation is
/// created only inside a project, so this is also the proof that the one on
/// screen has a workspace — the view forks here, and the onboarding branch is
/// the only place with no conversation to render.
fn Model::active_conversation(self : Model) -> Conversation? {
  self.find_conversation(self.focused, self.active_session)
}

///|
/// The user's current conversation intent. During navigation this is the
/// explicitly selected row; otherwise the loaded conversation is the
/// selection. Keeping that fallback here prevents lifecycle code from having
/// to choose independently between `selected_conversation` and
/// `active_session`.
fn Model::conversation_selection(self : Model) -> ConversationSelection? {
  match self.selected_conversation {
    Some(selected) => Some(selected)
    None =>
      self
      .active_conversation()
      .map(active => {
        channel: active.device,
        session: active.session_id,
        workspace: active.project(),
        record: if active.is_archived_read_only() {
          ArchivedRecord
        } else {
          LiveRecord
        },
      })
  }
}

///|
/// Resolve a component action against the conversation that currently owns
/// its local entry. An archive fact newer than the entry expires the action;
/// it must not reach either the archived record or a later reused id.
fn Model::conversation_for_composer_action(
  self : Model,
  identity : ComposerActionIdentity,
) -> Conversation? {
  let owner = identity.owner
  for
    index in identity.archive_generation..<self.composer_entry_retirements.length() {
    if self.composer_entry_retirements[index] == owner {
      return None
    }
  }
  self.find_conversation(owner.channel, owner.session)
}

///|
/// Whether the conversation on screen is a fresh "New chat" — nothing sent
/// yet and no stored record. While this holds, its project owns the sidebar
/// selection; the conversation itself appears there only after the first send.
fn Model::composing_new_chat(self : Model) -> Bool {
  guard self.active_conversation() is Some(conv) else { return false }
  self.conversation_is_new_chat(conv)
}

///|
/// The title switcher exists only while the visible OpenSeek draft still
/// belongs to a registered project. Keeping this predicate at the root lets
/// rendering, event admission, and post-update menu cleanup share one rule.
fn Model::can_choose_new_chat_project(self : Model) -> Bool {
  guard self.screen is Chat &&
    self.composing_new_chat() &&
    self.active_conversation() is Some(conv) &&
    self.focused_device() is Some(dev) else {
    return false
  }
  dev.projects.contains(conv.project())
}

///|
/// Whether `conv` is a live conversation the store does not know yet.
fn Model::conversation_is_new_chat(self : Model, conv : Conversation) -> Bool {
  if conv.has_begun() || conv.is_archived_read_only() {
    return false
  }
  guard self.device_state(conv.device) is Some(dev) else { return true }
  for item in dev.sessions {
    if item.id == conv.session_id && item.workspace == conv.project() {
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
    for input in conv.pending_steers {
      if input.submission_id == submission_id &&
        input.run_id is Some(owner) &&
        owner == run_id {
        return Some(conv)
      }
    }
  }
  None
}

///|
/// Whether this conversation is the transcript the reader can currently see.
/// Keeping this predicate separate from the unread bit makes window focus a
/// read-state input, not a second encoding of read state.
fn Model::conversation_is_visible(
  self : Model,
  channel : @interop.ChannelId,
  session_id : String,
) -> Bool {
  self.window_focused &&
  self.screen is Chat &&
  channel == self.focused &&
  session_id == self.active_session
}

///|
/// Mark one conversation's completed turn as read. Badge synchronization is
/// derived from the resulting model transition by `update`.
fn Model::mark_conversation_read(
  self : Model,
  channel : @interop.ChannelId,
  session_id : String,
) -> Model {
  let conversations = self.conversations.map(conv => {
    if conv.device == channel && conv.session_id == session_id {
      { ..conv, unseen_finish: false, }
    } else {
      conv
    }
  })
  { ..self, conversations, }
}

///|
/// A foreground chat reads the currently selected conversation through its
/// latest completion. Other screens retain the unread state until the reader
/// returns to the transcript.
fn Model::mark_visible_conversation_read(self : Model) -> Model {
  guard self.conversation_is_visible(self.focused, self.active_session) else {
    return self
  }
  self.mark_conversation_read(self.focused, self.active_session)
}

///|
/// Make `session_id` the on-screen conversation, creating its entry in
/// `project` when it has none, and drop conversations with nothing worth
/// keeping. Exact input ownership is retained even after lifecycle recovery
/// closes a run: a late id-bearing receipt or rejection may still retract a
/// warning or restore its draft. Abandoned "New chat" husks die here instead
/// of accumulating.
///
/// `project` places only a conversation this page has never held. One that
/// already exists keeps the workspace it was placed in, which may be a
/// worktree of that same project.
fn Model::activate(
  self : Model,
  channel : @interop.ChannelId,
  session_id : String,
  project : @common.Uri,
) -> Model {
  let conversations : Array[Conversation] = []
  let mut found = false
  for conv in self.conversations {
    if conv.device == channel && conv.session_id == session_id {
      found = true
      conversations.push(conv)
    } else if conv.worth_keeping() {
      conversations.push(conv)
    }
  }
  if !found {
    conversations.push(
      empty_conversation(
        channel,
        session_id,
        project,
        model=self
          .remembered_model(channel, session_id)
          .unwrap_or(self.default_model),
      ),
    )
  }
  // Activating a conversation is also what moves the UI's focus to its
  // device — a no-op while the app runs a single channel.
  let activated = {
    ..self,
    focused: channel,
    active_session: session_id,
    selected_conversation: conversations
    .iter()
    .find_first(conv => conv.device == channel && conv.session_id == session_id)
    .map(conv => {
      channel,
      session: session_id,
      workspace: conv.project(),
      record: if conv.is_archived_read_only() {
        ArchivedRecord
      } else {
        LiveRecord
      },
    }),
    conversation_load_failure: None,
    conversations,
  }
  // `activate` is the explicit navigation path into this transcript. A
  // background programmatic activation does not claim that the reader saw it;
  // the later window-focus event will mark it read once it is visible.
  if self.window_focused {
    activated.mark_conversation_read(channel, session_id)
  } else {
    activated
  }
}

///|
/// Whether the composer draft holds nothing at all — no typed text, no
/// mention chips, and no goal being written or awaiting its marker. This is
/// the retention test (`Model::activate` keeps a conversation whose draft
/// still holds anything), not the send gate: that is `draft_sendable`.
///
/// The goal halves count because `/goal` moves the user's text out of `task`:
/// without them a fresh conversation looks abandoned while holding the only
/// copy of a goal, and activating a neighbour would prune it away.
/// Whether this conversation is worth keeping once focus moves elsewhere:
/// it has begun, or it still holds writing that was never sent.
///
/// Retention and the sidebar row ask this same question, and have to. Keeping
/// one the list cannot reach does not save the draft, it strands it — the
/// conversation lives on in memory with no way back to it.
fn Conversation::worth_keeping(self : Conversation) -> Bool {
  self.has_begun() || !self.draft_empty()
}

///|
/// The registered project this conversation works in — its own root, or the
/// project that owns its worktree. Naming the project is not the same as
/// having a directory: a worktree's checkout is resolved from the registry
/// by `Model::conversation_placement`, which is what path-based work waits on.
fn Conversation::project(self : Conversation) -> @common.Uri {
  self.workspace.project()
}

///|
/// This conversation's worktree registry name, when it is bound to one.
fn Conversation::worktree_name(self : Conversation) -> String? {
  self.workspace.worktree_name()
}

///|
/// An archived transcript is display-only. Update handlers use this method
/// as the mutation gate; the read-only view is only its visible counterpart.
fn Conversation::is_archived_read_only(self : Conversation) -> Bool {
  self.record is ArchivedRecord
}

///|
fn Conversation::draft_empty(self : Conversation) -> Bool {
  self.task.is_blank() &&
  self.mentions.is_empty() &&
  !self.composer_draft_present &&
  !(self.goal_edit is Some(edit) && !edit.draft.is_blank()) &&
  self.goal_pending is None
}

///|
/// Whether the draft can be submitted. Typed text and explicit mention chips
/// are both prompt content; a mention-only draft sends its context envelope.
fn Conversation::draft_sendable(self : Conversation) -> Bool {
  !self.task.is_blank() || !self.mentions.is_empty()
}

///|
/// Whether the conversation has actually gotten under way — a run, durable
/// transcript, local notice, or exact submission ownership. A fresh "New
/// chat" (even with a typed draft) has not; the one on screen is represented
/// by its project, while stale husks stay out of the list.
/// The highest durable sequence this conversation knows of, including
/// commits buffered above the watermark while a reload is in flight.
///
/// A request's frontier has to be this and not `watermark`: a buffered
/// commit is already in hand, so a goal marker among them sits *below* what
/// the user just asked for — and under the watermark alone it would read as
/// above it, and confirm the new request with an older record's answer.
fn Conversation::durable_frontier(self : Conversation) -> Int {
  let mut frontier = self.watermark
  // Both buffering states, not just the live one: `begin_transcript_reload`
  // carries a failed read's buffer forward, so a marker held there is just as
  // much already-in-hand as one held by a reload still running.
  let buffered = match self.sync {
    Reloading(buffered~, ..) | ReloadFailed(buffered~, ..) => buffered
    Synced => []
  }
  for commit in buffered {
    if commit.sequence > frontier {
      frontier = commit.sequence
    }
  }
  frontier
}

///|
fn Conversation::has_begun(self : Conversation) -> Bool {
  self.is_running() ||
  self.messages.length() > 0 ||
  !self.pending_steers.is_empty()
}

///|
/// A run is in flight for this conversation — starting or open. The send
/// composer, sidebar pulse, and self-update busy check all gate on this.
fn Conversation::is_running(self : Conversation) -> Bool {
  !(self.run is NoRun(..))
}

///|
/// The sub-run lanes worth drawing: those belonging to the run that is open
/// right now. An idle conversation shows none, and a lane stranded by a
/// missing finish bracket cannot outlive its turn — the next run's lanes
/// carry the next run's id.
fn Conversation::visible_subruns(self : Conversation) -> Array[@subrun.Lane] {
  guard self.run is Open(run_id~, ..) else { return [] }
  @subrun.owned_by(self.turn.subruns, run_id)
}

///|
/// What the run is doing right now, as one line docked above the composer.
/// `None` between runs — an idle conversation reports nothing.
///
/// Purely derived from the run phase, like `display_status`, so no handler
/// has to keep a stored line in sync. Before the first reasoning delta this
/// only knows the current step. Once reasoning arrives, the transcript itself
/// becomes the progress indicator while this heartbeat continues to report
/// elapsed time.
/// The open turn as the composer's heartbeat row needs it: facts only. The
/// wording, the clock, and the tick that advances it belong to the composer,
/// so a span that changes every second costs one component's render instead
/// of reprojecting every component's input once a second.
fn Conversation::run_heartbeat(self : Conversation) -> @composer.RunHeartbeat? {
  let stage : @composer.RunStage = match self.run {
    NoRun(..) => return None
    Starting(..) => Starting
    Open(stage=Opened, ..) => Thinking
    Open(stage=AtStep(Some(step)), ..) => AtStep(step)
    Open(stage=AtStep(None), ..) => Working
    Open(stage=Cancelling, ..) => Stopping
  }
  Some({
    stage,
    started_ms: self.run_started_ms,
    tokens: self.turn.usage_tokens,
  })
}

///|
fn Conversation::clear_streams(self : Conversation) -> Conversation {
  {
    ..self,
    turn: { ..self.turn, streaming_response: None, live_reasoning: None, },
  }
}

///|
fn Conversation::clear_response(self : Conversation) -> Conversation {
  { ..self, turn: { ..self.turn, streaming_response: None, }, }
}

///|
fn Conversation::complete_reasoning(self : Conversation) -> Conversation {
  match self.turn.live_reasoning {
    Some(reasoning) if !reasoning.complete =>
      {
        ..self,
        turn: {
          ..self.turn,
          live_reasoning: Some({ ..reasoning, complete: true, }),
        },
      }
    _ => self
  }
}

///|
fn Model::allocate_submission_id(self : Model) -> (Model, String) {
  let sequence = self.submission_sequence + 1
  (
    { ..self, submission_sequence: sequence, },
    self.page_namespace + "-submission-" + sequence.to_string(),
  )
}

///|
fn Conversation::enqueue_steer(
  self : Conversation,
  submission_id : String,
  run_id : String?,
  content : String,
  draft : String,
  mentions : Array[Mention],
  behavior : FollowupBehavior,
) -> Conversation {
  let pending_steers = self.pending_steers.copy()
  pending_steers.push({
    submission_id,
    run_id,
    content,
    draft,
    mentions: mentions.copy(),
    behavior,
  })
  let queued_inputs = if behavior is FollowupQueue {
    let queued_inputs = self.queued_inputs.copy()
    queued_inputs.push({ id: submission_id, content, })
    queued_inputs
  } else {
    self.queued_inputs
  }
  { ..self, pending_steers, queued_inputs, }
}

///|
fn Conversation::remove_queued_input(
  self : Conversation,
  id : String,
) -> (Conversation, Bool) {
  for index, item in self.queued_inputs {
    if item.id == id {
      let queued_inputs = self.queued_inputs.copy()
      ignore(queued_inputs.remove(index))
      return (
        {
          ..self,
          queued_inputs,
          queue_edit_id: if self.queue_edit_id == Some(id) {
            None
          } else {
            self.queue_edit_id
          },
        },
        true,
      )
    }
  }
  (self, false)
}

///|
/// What the goal editor opens on: the newest goal text this conversation
/// knows of. A set still waiting for its marker is newer than the mirror —
/// the mirror is what the record carried *before* it — so editing during
/// that window continues what was sent rather than reverting to what it was
/// about to replace.
fn Conversation::goal_draft_seed(self : Conversation) -> String {
  match (self.goal_pending.map(pending => pending.request), self.goal) {
    (Some(Setting(text)), _) => text
    // A clear in flight is asking for nothing to stand, so it seeds nothing.
    (Some(Clearing), _) => ""
    (None, Some(goal)) => goal.text
    (None, None) => ""
  }
}

///|
/// Whether this conversation holds an outstanding intent that only the
/// durable record can settle. A goal command is the one left: its reply
/// carries no result, so the `[goal]` marker commit is the only place its
/// outcome appears. Prompts are not here — a prompt is sent once and the
/// transcript shows what became of it.
fn Conversation::awaits_durable_proof(self : Conversation) -> Bool {
  self.goal_pending is Some(_)
}

///|
fn Conversation::has_initial_submission(
  self : Conversation,
  submission_id : String,
) -> Bool {
  self.pending_prompt is Some(pending) && pending.submission_id == submission_id
}

///|
/// Whether this exact id-bearing receipt owns this entry. The run must match
/// too: a late echo from a finished run cannot consume a newer run's steer.
fn PendingSteer::matches_receipt(
  self : PendingSteer,
  submission_id : String,
  run_id : String?,
) -> Bool {
  self.submission_id == submission_id &&
  run_id is Some(run_id) &&
  self.run_id is Some(owner) &&
  owner == run_id
}

///|
fn Conversation::acknowledge_steer(
  self : Conversation,
  submission_id : String,
  run_id : String?,
) -> (Conversation, Bool) {
  for index, input in self.pending_steers {
    if input.matches_receipt(submission_id, run_id) {
      let pending_steers = self.pending_steers.copy()
      let _ = pending_steers.remove(index)
      return ({ ..self, pending_steers, }, true)
    }
  }
  (self, false)
}

///|

///|
/// Restore a definitively refused submission without overwriting a draft the
/// user typed while the request was in flight. Recovered text is placed first,
/// followed by the newer draft; mention chips retain both submissions' order.
fn Conversation::restore_submission(
  self : Conversation,
  draft : String,
  submitted_mentions : Array[Mention],
) -> Conversation {
  let task = if self.task.is_empty() {
    draft
  } else if draft.is_empty() || self.task == draft {
    self.task
  } else {
    draft + "\n\n" + self.task
  }
  let mentions = submitted_mentions.copy()
  for mention in self.mentions {
    mentions.push(mention)
  }
  { ..self, task, mentions, }
}

///|
/// Retire one definitively refused local submission and restore its composer
/// draft. The refusal itself is the caller's to report: no durable event will
/// ever carry it, so it is a toast, and the text is back in the composer where
/// the user can act on it.
fn Conversation::reject_steer(
  self : Conversation,
  submission_id : String,
  run_id : String?,
) -> (Conversation, Bool) {
  for index, input in self.pending_steers {
    if input.matches_receipt(submission_id, run_id) {
      let pending_steers = self.pending_steers.copy()
      let _ = pending_steers.remove(index)
      let next = { ..self, pending_steers, }
      return (next.restore_submission(input.draft, input.mentions), true)
    }
  }
  (self, false)
}

///|
/// Retire the prompt in flight because the host definitively refused it, and
/// put its draft back in the composer. The prompt was not written, so this is
/// news rather than a guess — the one outcome `pending_prompt` exists for.
fn Conversation::reject_pending_prompt(
  self : Conversation,
  submission_id : String,
) -> (Conversation, Bool) {
  guard self.pending_prompt is Some(pending) &&
    pending.submission_id == submission_id else {
    return (self, false)
  }
  (
    { ..self, pending_prompt: None, }.restore_submission(
      pending.draft,
      pending.mentions,
    ),
    true,
  )
}

///|
/// Retire the prompt in flight without recovering anything. Every ending that
/// is not a definite refusal comes here: the host answered, or the answer can
/// no longer arrive. Either way the draft's job is done — see
/// `Conversation::pending_prompt`.
fn Conversation::settle_pending_prompt(
  self : Conversation,
  submission_id : String,
) -> (Conversation, Bool) {
  guard self.pending_prompt is Some(pending) &&
    pending.submission_id == submission_id else {
    return (self, false)
  }
  ({ ..self, pending_prompt: None, }, true)
}

///|
/// Forget submissions whose transient acknowledgement cannot cross a
/// reconnect. Optimistic queue rows remain visible: the Desktop engine may
/// already hold them, and a later action or promoted Started boundary settles
/// their actual state without putting uncommitted text in the transcript.
fn Conversation::forget_awaiting_inputs(self : Conversation) -> Conversation {
  if self.pending_steers.is_empty() && self.pending_prompt is None {
    return self
  }
  let pending_steers : Array[PendingSteer] = []
  { ..self, pending_steers, pending_prompt: None, }
}

///|
/// Forget receipt-driven steers owned by this exact run. Queue-add requests
/// keep waiting for their direct host reply: unlike a steer receipt, that
/// reply can still arrive after the run's terminal event.
fn Conversation::forget_steers_for_run(
  self : Conversation,
  run_id : String,
) -> Conversation {
  let pending_steers = self.pending_steers.filter(input => {
    !(input.behavior is FollowupSteer &&
    input.run_id is Some(owner) &&
    owner == run_id)
  })
  if pending_steers.length() == self.pending_steers.length() {
    return self
  }
  { ..self, pending_steers, }
}

///|
/// Apply one durable commit's item to the transcript. Returns
/// whether the durable transcript visibly changed: a tool result can now fill
/// an existing call row without increasing the array length.
fn Conversation::apply_commit(
  self : Conversation,
  sequence : Int,
  item : @protocol.SessionItem,
  ts? : Double,
) -> (Bool, Conversation) {
  // A canonical User is transcript data, never local-submission ownership.
  // It is not a run boundary: the same kind also stores in-run steering.
  let messages = self.messages.copy()
  let changed = @transcript.apply_session_item(messages, item, ts?, sequence~)
  // A `[goal]` marker commit is the durable confirmation of a goal
  // set/clear/block — the only writer of the mirror the banner renders.
  let goal_marker = if item is @protocol.RuntimeNotice(notice) {
    @transcript.goal_marker(notice.content)
  } else {
    None
  }
  let goal = if goal_marker is Some(marker) {
    @transcript.apply_goal_marker(self.goal, marker)
  } else {
    self.goal
  }
  let conv = {
    ..self,
    messages,
    goal,
    // Settled by what this commit made the record say, not by whose command
    // it was — see `GoalRequest::settled_by`.
    goal_pending: if self.goal_pending is Some(pending) &&
      goal_marker is Some(marker) &&
      pending.request.settled_by(pending.since, [(sequence, marker)]) {
      None
    } else {
      self.goal_pending
    },
  }
  (changed, conv)
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
      { ..self, sync: ReloadFailed(generation~, buffered~), }
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
  goal~ : @transcript.GoalStanding?,
  goal_markers~ : Array[(Int, @transcript.GoalMarker)],
) -> (Conversation, Bool) {
  let (generation, pending) = match self.sync {
    Reloading(generation~, buffered~, ..) => (generation, buffered.copy())
    _ => return (self, false)
  }
  // Sequence order, whatever the arrival order was.
  pending.sort_by((a, b) => a.sequence - b.sequence)
  let reconciled = {
    ..self
    // The snapshot's reduced standing goal replaces the mirror wholesale;
    // buffered commits newer than the snapshot fold on top below through
    // `apply_commit`.
    ,
    goal,
    // A complete durable read is as good a settling point as a marker: if
    // the goal it reduces to is already what a request in flight asked
    // for, that request has nothing left to wait for. This is what ends
    // the wait after a delivery whose reply never came back — the reload
    // that follows a reconnect answers the question the transport could
    // not. A snapshot that does *not* show it settles nothing: the append
    // may still be queued behind this read.
    goal_pending: if self.goal_pending is Some(pending) &&
      pending.request.settled_by(pending.since, goal_markers) {
      None
    } else {
      self.goal_pending
    },
  }
  let mut conv : Conversation = {
    ..reconciled,
    messages: items,
    watermark,
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
        commit.item,
        ts?=commit.ts,
      )
      conv = { ..next, watermark: commit.sequence, }
    } else {
      leftover.push(commit)
    }
  }
  if leftover.is_empty() {
    (conv, false)
  } else {
    ({ ..conv, sync: ReloadFailed(generation~, buffered=leftover), }, true)
  }
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
    MaxStepsExhausted => "Max steps exhausted"
    // An empty wire status reads as a plain finish, like `parse`'s inverse.
    Unknown(wire) => if wire.is_blank() { "Finished" } else { wire }
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
