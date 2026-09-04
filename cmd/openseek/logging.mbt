///|
/// The CLI's `@xlog` policy: every entry is discarded.
///
/// Protocol events do not go through `@xlog`: `@emit` writes each event's line
/// to its own stdout sink (`openseek_protocol/emit`), which `with_jsonl_stdout`
/// opens and drains for a streaming run. Nothing linked into this binary
/// currently logs through `@xlog` at all, so there is no genuine log content
/// to route anywhere. The handler is pinned anyway because `@xlog`'s default
/// handler writes to stdout, which must stay a pure protocol stream
/// (`run`/`serve`/`subrun`) or exactly the command's own output (`review`'s
/// report, `mcp`'s summary, `sessions`' text): a stray log line from a future
/// dependency must never reach it. `dispatch` installs this once, before any
/// subcommand runs.
///
/// Nothing here sets a level: the stdout protocol no longer depends on one.
priv struct DiscardLog {}

///|
impl @xlog.Handler for DiscardLog with fn handle(
  _self : DiscardLog,
  _entry : @xlog.Entry,
) -> Unit raise {

}

///|
fn configure_logging() -> Unit {
  @xlog.global().set_handler(DiscardLog::{ })
}
