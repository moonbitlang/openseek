// Wire-traffic logging for the LSP transport. The host points this at a
// dedicated `lsp.log` so the noisy per-message stream stays out of the main app
// log; until then (e.g. in tests) traffic is simply not recorded.

///|
/// The logger the transport mirrors every LSP message to. `None` until the host
/// calls `enable_traffic_log`.
let traffic_logger : Ref[@xlog.Logger?] = Ref(None)

///|
/// Route LSP wire traffic to a fresh file handler at `path` (typically
/// `<runtime>/lsp.log`), replacing any previous destination. Best-effort: if the
/// file cannot be opened, traffic logging stays off rather than failing host
/// startup. xlog's file handler appends, so re-runs accumulate in one file.
pub fn enable_traffic_log(path : String) -> Unit {
  let logger = @xlog.Logger(@xlog.File(path), level=Debug) catch { _ => return }
  traffic_logger.val = Some(logger)
}

///|
/// Record one message on the traffic log, when one is configured, tagged with
/// `event` (`lsp_send`/`lsp_recv`) and the `server` it belongs to so several
/// moon-lsp servers can be told apart in the shared file.
fn log_traffic(event : String, server : String, message : Json) -> Unit {
  guard traffic_logger.val is Some(logger) else { return }
  logger.debug(category="lsp") <?
    { "event": event, "server": server, "message": message }
}
