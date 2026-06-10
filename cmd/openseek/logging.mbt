///|
/// Bridge from `@xlog`'s synchronous `Handler` to unbuffered stdout writes.
///
/// The TUI parses the JSONL the engine writes to stdout through a pipe. Plain
/// `println` goes through C stdio, which is block-buffered on a pipe, so
/// streaming deltas would all arrive at once. `@stdio.stdout` writes the fd
/// directly through the event loop instead — one write per line, no userspace
/// buffer — but it is asynchronous while `Handler::handle` is not. The handler
/// therefore enqueues each formatted line, and `drain` (spawned for the run by
/// `run_cli`) writes them out in order.
///
/// The queue is unbounded, so `try_put` only fails once the queue is closed —
/// that is, for an entry logged after the run already ended — and dropping
/// such an entry matches the process being on its way out.
priv struct FlushedStdout {
  format : @xlog.Format
  lines : @async.Queue[String]
}

///|
fn FlushedStdout::FlushedStdout(
  format? : @xlog.Format = Jsonl,
) -> FlushedStdout {
  { format, lines: Queue(kind=Unbounded) }
}

///|
impl @xlog.Handler for FlushedStdout with fn handle(
  self : FlushedStdout,
  entry : @xlog.Entry,
) -> Unit raise {
  let line = match self.format {
    Text => entry.to_string()
    Jsonl => entry.to_json().stringify()
  }
  self.lines.try_put(line) |> ignore
}

///|
/// Write queued log lines to stdout until the queue is closed and drained.
/// `Queue::get` keeps returning buffered lines after `close`, so closing never
/// loses events that were logged before it.
async fn FlushedStdout::drain(self : FlushedStdout) -> Unit {
  for ;; {
    let line = self.lines.get() catch {
      error if @async.is_cancellation_error(error) => raise error
      // The queue is closed and empty: every logged line has been written.
      // This must not test `is_being_cancelled`: when the run body fails, the
      // `defer` close and the group's cancellation race, and re-raising the
      // close error here would replace the run's real failure with
      // `QueueAlreadyClosed` in the report the user sees.
      _ => return
    }
    @stdio.stdout.write(line + "\n")
  }
}

///|
fn FlushedStdout::close(self : FlushedStdout) -> Unit {
  self.lines.close()
}

///|
/// Route every JSONL log event to the flushed-stdout queue. When
/// `OPENSEEK_LOG_FILE` is set, mirror each event there as well; the file
/// handler flushes per entry, so `tail -f $OPENSEEK_LOG_FILE` shows events
/// live. Best-effort: if the file cannot be opened, logging stays
/// stdout-only rather than failing the run.
fn configure_logging() -> FlushedStdout {
  let stdout = FlushedStdout()
  guard @env.get_env_var("OPENSEEK_LOG_FILE") is Some(path) && path != "" else {
    @xlog.global().set_handler(stdout)
    return stdout
  }
  let file = @xlog.File::File(path) catch {
    _ => {
      @xlog.global().set_handler(stdout)
      return stdout
    }
  }
  let handlers : Array[&@xlog.Handler] = [stdout, file]
  @xlog.global().set_handler(@xlog.Multi(handlers))
  stdout
}
