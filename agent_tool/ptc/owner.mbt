// The program behind a host call, as a tool that needs to know it sees it.
//
// A host tool's executor receives arguments and nothing else, which is right
// for `edit` or `write`: what they do does not depend on who asked. A tool
// that starts something on a script's behalf does depend on it. It must know
// which script the thing belongs to, so that it can be found again by that
// script only, and ended when the script ends.
//
// That identity cannot ride in the arguments — the script writes those. So
// the service builds each program its OWN instances of such tools, closed
// over an `Owner` the host created. Direct calls and every other tool are
// untouched: an executor is still `(Json) -> ToolAction`.

///|
/// One registered program, for the tools built for it.
///
/// It is alive from registration until the program is stopped: it exits, is
/// cancelled, or its job is stopped. A dropped connection does not stop a
/// program, and neither does moving to the background — adoption keeps the
/// same owner and only fills in the job id.
struct Owner {
  id : String
  mut closed : Bool
  mut job : String?
  stops : Array[() -> Unit]
  closes : Array[async () -> Unit noraise]
}

///|
/// A stable name for this program, unique within its service.
pub fn Owner::id(self : Owner) -> String {
  self.id
}

///|
/// True once the program has been stopped. A tool that suspends — to write
/// a record, say — must look again afterwards: the program may have ended
/// while it waited, and what it was about to start would have no owner.
pub fn Owner::is_closed(self : Owner) -> Bool {
  self.closed
}

///|
/// The background job that adopted this program, once one has.
pub fn Owner::job(self : Owner) -> String? {
  self.job
}

///|
/// Run `hook` when the program is stopped: synchronously, with no suspension,
/// at the same moment its capability is revoked. For ending admission —
/// marking what the program owns as no longer startable.
///
/// Register hooks when the tools are built, in the factory. A hook added
/// after the program has stopped runs at once.
pub fn Owner::on_stop(self : Owner, hook : () -> Unit) -> Unit {
  if self.closed {
    hook()
  } else {
    self.stops.push(hook)
  }
}

///|
/// Run `hook` when the program is closed: after its calls in flight have been
/// joined, and awaited before the program's final trace is published. For
/// stopping and joining what the program owns.
///
/// A program may be closed more than once, and by more than one caller at a
/// time, and every close waits for the same things: a hook must be safe to
/// run again and to run concurrently with itself. It cannot raise — a
/// failure to clean up one thing must not skip the rest — but it CAN hang,
/// and a hook that never returns holds up the program's close, every hook
/// after it, and the session's shutdown. A hook bounds its own waits.
///
/// Register hooks when the tools are built, in the factory. One added while
/// a close is already running is not seen by that close.
pub fn Owner::on_close(self : Owner, hook : async () -> Unit noraise) -> Unit {
  self.closes.push(hook)
}

///|
/// Stop: end admission and run the stop hooks, once.
fn Owner::stop(self : Owner) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  for hook in self.stops {
    hook()
  }
}

///|
/// Close: run every close hook and wait for each.
async fn Owner::close(self : Owner) -> Unit noraise {
  for hook in self.closes {
    hook()
  }
}
