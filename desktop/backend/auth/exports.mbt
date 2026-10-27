// Public items this package exports on purpose, whose consumers the
// workspace-only analyzer cannot see. Each block says who the consumer is.

///|
/// What the connector needs to run — one shape for both a signed-in
/// session (derived) and the `OPENSEEK_RELAY_URL`/`OPENSEEK_DEVICE_TOKEN`
/// development override (verbatim). Exported `pub(all)` for the window host
/// in `desktop/app`, a module outside this workspace: `relay_settings` in
/// `desktop/app/main.mbt` builds the override with a `ConnectorConfig`
/// struct literal.
pub(all) struct ConnectorConfig {
  relay_url : String
  device_token : String
  device_name : String
} derive(Eq)

///|
/// Load the persisted sign-in (when there is a runtime dir to read from).
/// The environment override controls only the relay, independently of the
/// persisted account session. The override itself is never persisted.
/// Exported for two consumers the analyzer cannot see as uses of a public
/// API: the window host `desktop/app` (a separate module, which loads the
/// store at startup in `desktop/app/main.mbt`), and the test seam the
/// `desktop/backend/api` whitebox tests use to open a store rooted at a temp
/// runtime dir (`session_share_wbtest.mbt`, `file_share_wbtest.mbt`).
pub async fn AuthStore::load(
  runtime_dir? : @pathx.Path,
  env_override? : ConnectorConfig,
) -> AuthStore {
  let session = match runtime_dir {
    Some(dir) => load_session_file(dir)
    None => None
  }
  {
    runtime_dir,
    env_override,
    wakeups: Queue(kind=DiscardOldest(1)),
    session,
    connected: false,
    override_device: None,
    rejected: false,
    persist_mutex: Mutex(),
    remote_generation: 0,
    sign_in_active: false,
    sign_in_abort: Queue(kind=DiscardOldest(1)),
  }
}
