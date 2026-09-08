///|
/// Arguments of the immediate job_output read. An absent/null offset means
/// the recent tail; a supplied offset selects a window from the start.
pub struct JobOutputInput {
  job_id : String
  offset : Int?
} derive(Debug)

///|
/// Decode arguments locally because the dispatcher does not enforce schemas.
/// Reject the removed waiting parameter with guidance for older callers.
pub fn decode(arguments : Json) -> JobOutputInput raise {
  guard arguments is { "job_id": String(job_id), .. } else {
    fail("job_output requires a string job_id")
  }
  if arguments is { "wait_ms": _, .. } {
    fail("job_output no longer accepts wait_ms; use job_wait with job_ids")
  }
  { job_id, offset: offset(arguments), }
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
