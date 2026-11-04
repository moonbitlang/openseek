///|
/// A JSONL log file that `LogFile::append` extends one record at a time.
///
/// `append` only queues the line; the task `with_log_file` runs writes the
/// queue out in order. The file is open in append mode and every line goes
/// out in one write, so several processes can share it without overwriting
/// or interleaving each other's lines.
struct LogFile {
  lines : @aqueue.Queue[String]
}

///|
/// Queue `record` as one JSONL line. Raises once `with_log_file` has
/// returned and the file is closed.
pub fn LogFile::append(self : LogFile, record : Json) -> Unit raise {
  ignore(self.lines.try_put("\{record.stringify()}\n"))
}

///|
/// Open `path` for appending, creating it when missing, and run `body` with
/// it. Lines appended while `body` runs are written by a background task, and
/// all of them are on disk when this returns — also when `body` raises, which
/// is when a launch log matters most. Write failures drop the line.
pub async fn with_log_file(
  path : String,
  body : async (LogFile) -> Unit,
) -> Unit {
  let file = @fs.open(
    path,
    mode=WriteOnly,
    append=true,
    create_mode=OpenOrCreate,
  )
  defer file.close()
  let log = { lines: Queue(kind=Unbounded), }
  // A task group cancels its tasks when its body raises, so the body's error
  // is held until the writer has drained the queue.
  let failure = @async.with_task_group(group => {
    group.spawn_bg(() => {
      for ;; {
        let line = log.lines.get() catch {
          @aqueue.QueueAlreadyClosed => break
          error => raise error
        }
        file.write(line) catch {
          _ => ()
        }
      }
    })
    defer log.lines.close()
    try body(log) catch {
      error => Some(error)
    } noraise {
      _ => None
    }
  })
  if failure is Some(error) {
    raise error
  }
}
