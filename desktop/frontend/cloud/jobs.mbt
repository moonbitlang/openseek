///|
#derive(Eq)
pub struct JobConnection {
  token : String
  session : String
  stream : StreamLease
}

///|
pub extend JobConnection with Eq::{equal, not_equal}

///|
pub fn Conversation::job_connection(
  self : Conversation,
  token : String,
  session : String,
) -> JobConnection? {
  guard self.stream is Some(stream) && stream.active && self.last_seq is Some(_) else {
    return None
  }
  Some({ token, session, stream, })
}

///|
async fn JobConnection::request(
  self : JobConnection,
  request_id : String,
  command : @wire.Command,
) -> @wire.Event? {
  guard self.stream.active else {
    raise @cloud_client.RequestError(Unreachable)
  }
  let reply : @async.Queue[@wire.Event] = Queue(kind=Blocking(1))
  self.stream.job_replies[request_id] = reply
  defer self.stream.job_replies.remove(request_id)
  match send_command(self.token, self.session, command) {
    Rejected("instance_not_running") => None
    Rejected(reason) => raise @cloud_client.RequestError(RemoteMessage(reason))
    Accepted => Some(@async.with_timeout(30000, () => reply.get()))
  }
}

///|
pub async fn JobConnection::list_jobs(
  self : JobConnection,
) -> @protocol.JobsListReply {
  let request_id = @uuid.mint()
  let jobs = match self.request(request_id, JobsSnapshot(request_id~)) {
    None => []
    Some(JobsSnapshot(jobs~, ..)) => jobs
    _ => raise @cloud_client.RequestError(Malformed)
  }
  {
    jobs: jobs.map(job => {
      job,
      output_path: None,
      controllable: !job.state.is_terminal(),
      error: None,
    }),
    next_offset: None,
    selected: None,
    errors: [],
  }
}

///|
pub async fn JobConnection::stop_job(
  self : JobConnection,
  generation : String,
  job_id : String,
) -> @protocol.JobStopReply {
  let request_id = @uuid.mint()
  match self.request(request_id, JobStop(request_id~, generation~, job_id~)) {
    Some(JobStopResult(generation=g, job_id=id, outcome~, ..)) if g ==
      generation &&
      id == job_id => { outcome, }
    None =>
      raise @cloud_client.RequestError(RemoteMessage("No running instance"))
    _ => raise @cloud_client.RequestError(Malformed)
  }
}
