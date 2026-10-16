///|
struct PreparationJob {
  token : @protocol.SshPreparationToken
  request : @protocol.SshPreparationRequest
  mut stage : String
  mut activation_started : Bool
  mut cancelled : Bool
  mut started : Bool
  mut task : @async.Task[@protocol.SshProfile]?
}

///|
/// A reservation is returned before execution. Cancellation of that reservation
/// wins even when the renderer's execute request has not arrived yet.
pub struct Preparation {
  mut job : PreparationJob?
}

///|
pub fn Preparation::Preparation() -> Preparation {
  { job: None, }
}

///|
pub fn Preparation::begin(
  self : Preparation,
  request : @protocol.SshPreparationRequest,
) -> @protocol.SshPreparationToken raise {
  guard self.job is None else {
    raise SshError("This window already has a preparation in progress")
  }
  let token : @protocol.SshPreparationToken = { id: @uuid.mint(), }
  self.job = Some({
    token,
    request,
    stage: "reserved",
    activation_started: false,
    cancelled: false,
    started: false,
    task: None,
  })
  token
}

///|
pub fn Preparation::progress(
  self : Preparation,
  token : @protocol.SshPreparationToken,
) -> @protocol.SshPreparationProgress {
  {
    stage: match self.job {
      Some(job) if job.token.id == token.id => Some(job.stage)
      _ => None
    },
  }
}

///|
pub async fn Preparation::execute(
  self : Preparation,
  token : @protocol.SshPreparationToken,
  operation : async (@protocol.SshPreparationRequest, (String) -> Unit) -> @protocol.SshProfile,
) -> @protocol.SshProfile {
  guard self.job is Some(job) &&
    job.token.id == token.id &&
    !job.started &&
    !job.cancelled else {
    raise SshError(
      "Preparation was cancelled or superseded; start a new attempt",
    )
  }
  job.started = true
  defer {
    self.job = None
  }
  @async.with_task_group(group => {
    let task = group.spawn(
      () => {
        operation(job.request, stage => {
          job.stage = stage
          if stage == "activate" {
            job.activation_started = true
          }
        })
      },
      allow_failure=true,
    )
    job.task = Some(task)
    task.wait() catch {
      @async.WaitedTaskAlreadyCancelled =>
        raise SshError(
          if job.activation_started {
            "Preparation cancelled during activation; inspect the remote daemon and upgrade records before retrying"
          } else {
            "Preparation cancelled"
          },
        )
      error => raise error
    }
  })
}

///|
pub async fn Preparation::cancel(
  self : Preparation,
  token : @protocol.SshPreparationToken,
) -> Unit {
  guard self.job is Some(job) && job.token.id == token.id else { return }
  job.cancelled = true
  job.stage = "cancelling"
  if job.task is Some(task) {
    task.cancel()
    ignore(task.wait()) catch {
      _ => ()
    }
  } else {
    self.job = None
  }
}

///|
pub async fn Preparation::close(self : Preparation) -> Unit {
  if self.job is Some(job) {
    self.cancel(job.token)
  }
}
