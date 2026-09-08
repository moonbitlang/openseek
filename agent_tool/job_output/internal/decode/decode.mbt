///|
/// Decoded arguments of the `job_output` tool: the `job_id` of the background
/// job to read, plus the optional `wait_ms` and `offset` selectors. Either
/// selector is `None` when the caller omits it (or passes `null`): `None`
/// `wait_ms` means no waiting, `None` `offset` means the recent tail.
pub struct JobOutputInput {
  job_id : String
  wait_ms : Int?
  offset : Int?
} derive(Debug)

///|
/// Longest a single `job_output` call may block awaiting a job, so one tool
/// call cannot hold the turn indefinitely; the model can always call again. A
/// caller that asks for longer is capped to this, not rejected — the cap is a
/// bounded wait, and the response still reports the job running if the wait
/// expires.
pub let max_wait_ms : Int = 120_000

///|
/// Decode `job_output` tool-call arguments.
///
/// `job_id` is a required string naming the background job to read. `wait_ms`,
/// when present, must be a positive number and is capped at `max_wait_ms`;
/// absent or null means no waiting. `offset`, when present, must be zero or a
/// positive number; absent or null means the recent tail. The local dispatcher
/// does not enforce the JSON schema, so the decoder must: failures name the
/// argument to fix.
pub fn decode(arguments : Json) -> JobOutputInput raise {
  match arguments {
    { "job_id": String(job_id), .. } =>
      { job_id, wait_ms: wait_ms(arguments), offset: offset(arguments), }
    _ => fail("job_output requires a string job_id")
  }
}

///|
/// Decode the optional `wait_ms` argument: a positive number, capped at
/// `max_wait_ms`. Absent/null means no waiting.
fn wait_ms(arguments : Json) -> Int? raise {
  match arguments {
    { "wait_ms": Number(value, ..), .. } => {
      let wait = value.to_int()
      if wait <= 0 {
        fail("job_output wait_ms must be a positive number")
      } else if wait > max_wait_ms {
        Some(max_wait_ms)
      } else {
        Some(wait)
      }
    }
    { "wait_ms": Null, .. } => None
    // Present but not a number (e.g. a stringified "30000"): reject rather
    // than silently skip the wait.
    { "wait_ms": _, .. } => fail("job_output wait_ms must be a number")
    _ => None
  }
}

///|
/// Decode the optional `offset` argument: a character offset from the start of
/// the captured output, zero or more. Absent/null means the recent tail.
fn offset(arguments : Json) -> Int? raise {
  match arguments {
    { "offset": Number(value, ..), .. } => {
      let offset = value.to_int()
      if offset < 0 {
        fail("job_output offset must be zero or a positive number")
      } else {
        Some(offset)
      }
    }
    { "offset": Null, .. } => None
    { "offset": _, .. } => fail("job_output offset must be a number")
    _ => None
  }
}

///|
pub extend JobOutputInput with Debug::{to_repr}
