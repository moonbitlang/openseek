///|
struct ActionsMonitor {
  attached : @async.Queue[Unit]
  watches : Map[String, ActionsPullRequest]
}

///|
priv struct ActionsPullRequest {
  subscribers : Map[String, ActionsWatch]
  mut retry_at : Int64
}

///|
priv struct ActionsWatch {
  samples : @async.Queue[ActionsSample]
  mut task : @async.Task[Unit]?
}

///|
priv struct ActionsSample {
  round : Int64
  snapshot : @github.PullRequestCheckSnapshot
}

///|
pub fn ActionsMonitor::ActionsMonitor() -> ActionsMonitor {
  { attached: Queue(kind=DiscardOldest(1)), watches: Map([]), }
}

///|
/// Run the monitor and its delivery workers until the caller cancels it.
pub async fn ActionsMonitor::start(
  self : ActionsMonitor,
  notify~ : async (Notice) -> Unit,
) -> Unit {
  @async.with_task_group(group => self.poll(group, notify))
}

///|
pub fn ActionsMonitor::stop_session(
  self : ActionsMonitor,
  session~ : String,
) -> Unit {
  for url in self.watches.keys().collect() {
    if self.remove_watch(session, url) is Some({ task: Some(task), .. }) {
      task.cancel()
    }
  }
}

///|
fn ActionsMonitor::remove_watch(
  self : ActionsMonitor,
  session : String,
  url : String,
  expected? : ActionsWatch,
) -> ActionsWatch? {
  guard self.watches.get(url) is Some(pr) &&
    pr.subscribers.get(session) is Some(watch) else {
    return None
  }
  // A finishing worker must not remove a replacement for this subscription.
  guard !(expected is Some(previous) && !physical_equal(previous, watch)) else {
    return None
  }
  pr.subscribers.remove(session)
  if pr.subscribers.is_empty() {
    self.watches.remove(url)
  }
  Some(watch)
}

///|
/// Replace one session's subscriptions from its committed artifact snapshot.
/// Registration is synchronous and can precede `start`.
pub fn ActionsMonitor::set_artifacts(
  self : ActionsMonitor,
  session~ : String,
  artifacts~ : @protocol.SessionArtifacts,
) -> Unit {
  let urls : Set[String] = Set([])
  for artifact in artifacts.artifacts {
    guard artifact.type_ is PullRequest &&
      @github.canonical_pull_request_url(artifact.url) is Some(url) else {
      continue
    }
    urls.insert(url)
  }
  for url in self.watches.keys().collect() {
    if !urls.contains(url) &&
      self.remove_watch(session, url) is Some({ task: Some(task), .. }) {
      task.cancel()
    }
  }
  for url in urls {
    let pr = self.watches.get_or_init(url, () => {
      subscribers: Map([]),
      retry_at: 0L,
    })
    guard !pr.subscribers.contains(session) else { continue }
    pr.subscribers[session] = {
      samples: Queue(kind=DiscardOldest(1)),
      task: None,
    }
    ignore(self.attached.try_put(()) catch { _ => false })
  }
}

///|
fn contains_pr(artifacts : @protocol.SessionArtifacts, url : String) -> Bool {
  artifacts.artifacts.any(artifact => {
    artifact.type_ is PullRequest &&
    @github.canonical_pull_request_url(artifact.url) == Some(url)
  })
}

///|
async fn ActionsMonitor::poll(
  self : ActionsMonitor,
  group : @async.TaskGroup,
  notify : async (Notice) -> Unit,
) -> Unit {
  let mut round = 0L
  for ;; {
    while self.watches.is_empty() {
      self.attached.get()
    }
    let now = @async.now()
    let pending : Array[(String, ActionsPullRequest)] = []
    for url, pr in self.watches {
      if pr.retry_at <= now {
        pending.push((url, pr))
      }
    }
    if !pending.is_empty() {
      round += 1
      let snapshots = @github.pull_request_checks_batch(
        pending.map(entry => entry.0),
      )
      for (url, pr) in pending {
        guard self.watches.get(url) is Some(live) &&
          physical_equal(pr, live) &&
          snapshots.get(url) is Some(snapshot) else {
          continue
        }
        pr.retry_at = if snapshot is ChecksUnavailable(_) {
          @async.now() + 60000L
        } else {
          0L
        }
        for session, watch in pr.subscribers {
          if watch.task is None {
            watch.task = Some(
              group.spawn(no_wait=true, allow_failure=true, () => {
                self.watch_actions(session, url, watch, notify)
              }),
            )
          }
          ignore(
            watch.samples.try_put({ round, snapshot, }) catch {
              _ => false
            },
          )
        }
        if snapshot is ChecksClosed {
          self.watches.remove(url)
        }
      }
    }
    @async.sleep(15000)
  }
}

///|
#derive(Eq)
pub enum Outcome {
  Failed
  Passed
}

///|
pub struct Notice {
  session : String
  url : String
  head : String
  outcome : Outcome
}

///|
async fn ActionsMonitor::watch_actions(
  self : ActionsMonitor,
  session : String,
  url : String,
  watch : ActionsWatch,
  notify : async (Notice) -> Unit,
) -> Unit {
  defer ignore(self.remove_watch(session, url, expected=watch))
  let mut previous_head = None
  let mut green : (Int64, Array[String])? = None
  let mut reported : Outcome? = None
  let mut unavailable = false
  for ;; {
    let sample = watch.samples.get()
    if sample.snapshot is ChecksClosed {
      return
    }
    // Re-read the saved list because a different host can remove the PR or
    // archive the session while the shared GitHub request is in flight.
    let snapshot : @github.PullRequestCheckSnapshot = try {
      let artifacts = @session_store.list_artifacts(session)
      guard contains_pr(artifacts, url) else { return }
      sample.snapshot
    } catch {
      error => ChecksUnavailable("\{error}")
    }
    let (head, checks) = match snapshot {
      ChecksClosed => return
      ChecksOpen(head~, checks~) => (head, checks)
      ChecksUnavailable(error) => {
        if !unavailable {
          if @xlog.warn() is Some(w) {
            w
            ..write_object_begin()
            ..write_object_field("event", "actions_monitor_unavailable")
            ..write_object_field("session", session)
            ..write_object_field("pr", url)
            ..write_object_field("error", error)
            .write_object_end()
          }
        }
        unavailable = true
        green = None
        continue
      }
    }
    unavailable = false
    if previous_head != Some(head) {
      previous_head = Some(head)
      green = None
      reported = None
    }
    let outcome = match checks {
      ChecksFailed => {
        green = None
        Some(Failed)
      }
      ChecksWaiting(retrying~) => {
        green = None
        if retrying {
          reported = None
        }
        None
      }
      ChecksPassed(checks) => {
        let settled = green == Some((sample.round - 1L, checks))
        green = Some((sample.round, checks))
        if settled {
          Some(Passed)
        } else {
          None
        }
      }
    }
    if outcome is Some(outcome) && reported != Some(outcome) {
      notify({ session, url, head, outcome, })
      reported = Some(outcome)
    }
  }
}
