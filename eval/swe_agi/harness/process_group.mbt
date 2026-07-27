///|
/// A command whose descendants must not outlive the command itself.
priv struct ProcessGroupCommand {
  program : String
  args : Array[String]
}

///|
/// Keep the executable and its arguments together until platform-specific
/// process containment is applied.
fn ProcessGroupCommand::ProcessGroupCommand(
  program~ : String,
  args~ : Array[String],
) -> ProcessGroupCommand {
  { program, args }
}

///|
/// This runner currently depends on POSIX `rsync`, `find`, process groups, and
/// signals. Refuse to run on Windows instead of pretending that cancelling one
/// PID also terminates its descendants.
#cfg(not(platform="windows"))
fn ProcessGroupCommand::supported() -> Bool {
  true
}

///|
#cfg(platform="windows")
fn ProcessGroupCommand::supported() -> Bool {
  false
}

///|
/// On POSIX, a small Python supervisor creates a new session before executing
/// the real command. Unlike shell job control, `setsid()` also works under
/// Ubuntu's non-interactive `/bin/sh` (dash). The supervisor remains outside
/// that session, forwards cancellation to the whole process group, and removes
/// ordinary descendants after the group leader exits.
///
/// This is lifecycle containment, not a hostile-process sandbox: a submitted
/// program can deliberately escape with another `setsid()`. Private inputs
/// therefore remain held out against normal agent behavior, while stronger
/// adversarial isolation still requires a container or OS sandbox.
#cfg(not(platform="windows"))
fn ProcessGroupCommand::wrapped(
  self : ProcessGroupCommand,
) -> (String, Array[String]) {
  let supervisor =
    #|import os
    #|import signal
    #|import sys
    #|import time
    #|
    #|class ProcessSupervisor:
    #|    def __init__(self):
    #|        self.child = 0
    #|        self.forwarded_signals = (
    #|            signal.SIGTERM,
    #|            signal.SIGINT,
    #|            signal.SIGHUP,
    #|        )
    #|
    #|    def terminate(self, signum, _frame):
    #|        if self.child:
    #|            try:
    #|                os.killpg(self.child, signal.SIGTERM)
    #|            except ProcessLookupError:
    #|                pass
    #|            time.sleep(1)
    #|            try:
    #|                os.killpg(self.child, signal.SIGKILL)
    #|            except ProcessLookupError:
    #|                pass
    #|        os._exit(128 + signum)
    #|
    #|    def run(self):
    #|        previous_mask = signal.pthread_sigmask(
    #|            signal.SIG_BLOCK, self.forwarded_signals
    #|        )
    #|        for signum in self.forwarded_signals:
    #|            signal.signal(signum, self.terminate)
    #|        ready_read, ready_write = os.pipe()
    #|        child = os.fork()
    #|        if child == 0:
    #|            try:
    #|                os.close(ready_read)
    #|                os.setsid()
    #|                os.write(ready_write, b"1")
    #|                os.close(ready_write)
    #|                for signum in self.forwarded_signals:
    #|                    signal.signal(signum, signal.SIG_DFL)
    #|                signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
    #|                os.execvp(sys.argv[1], sys.argv[1:])
    #|            except BaseException as error:
    #|                print(
    #|                    "SWE-AGI process supervisor could not exec: "
    #|                    + str(error),
    #|                    file=sys.stderr,
    #|                )
    #|                os._exit(127)
    #|        os.close(ready_write)
    #|        self.child = child
    #|        os.read(ready_read, 1)
    #|        os.close(ready_read)
    #|        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
    #|        _, status = os.waitpid(child, 0)
    #|        try:
    #|            os.killpg(child, 0)
    #|        except ProcessLookupError:
    #|            pass
    #|        else:
    #|            os.killpg(child, signal.SIGTERM)
    #|            time.sleep(1)
    #|            try:
    #|                os.killpg(child, signal.SIGKILL)
    #|            except ProcessLookupError:
    #|                pass
    #|        if os.WIFEXITED(status):
    #|            return os.WEXITSTATUS(status)
    #|        if os.WIFSIGNALED(status):
    #|            return 128 + os.WTERMSIG(status)
    #|        return 1
    #|
    #|sys.exit(ProcessSupervisor().run())
  let args = ["-c", supervisor, self.program]
  args.append(self.args)
  ("python3", args)
}

///|
/// Unreachable after `Config::run` checks `supported()`. Keeping this branch
/// typed lets the package compile on Windows while producing an explicit
/// runtime error before any trial workspace or protected input is created.
#cfg(platform="windows")
fn ProcessGroupCommand::wrapped(
  self : ProcessGroupCommand,
) -> (String, Array[String]) {
  (self.program, self.args)
}
