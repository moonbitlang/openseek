// Background job requests are scoped to a conversation and host command channel.
// Optional values accept missing/null; malformed present fields are rejected.
// Unknown object fields are ignored. Integers are exact nonnegative JSON numbers.

///|
fn jobs_uint(
  value : Json,
  path : @json.JsonPath,
) -> Int64 raise @json.JsonDecodeError {
  match value {
    Number(n, ..) if n >= 0 &&
      n <= 9007199254740991.0 &&
      n.to_int64().to_double() == n => n.to_int64()
    _ => raise JsonDecodeError((path, "expected exact nonnegative integer"))
  }
}

///|
pub(all) struct JobsScope {
  session : String
  workspace : String?
  archived : Bool
} derive(Eq, Debug)

///|
pub impl FromJson for JobsScope with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "JobsScope")
  let session : String = @json.from_json(
    obj.required_json("session"),
    path=path.add_key("session"),
  )
  let workspace : String? = match obj.optional_json("workspace") {
    None => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("workspace")))
  }
  let archived : Bool = @json.from_json(
    obj.required_json("archived"),
    path=path.add_key("archived"),
  )
  guard !session.is_empty() else {
    raise JsonDecodeError((path, "empty session"))
  }
  { session, workspace, archived, }
}

///|
pub impl ToJson for JobsScope with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = self.session.to_json()
  if self.workspace is Some(value) {
    fields["workspace"] = value.to_json()
  }
  fields["archived"] = self.archived.to_json()
  fields.to_json()
}

///|
pub extend JobsScope with Eq::{equal, not_equal}

///|
pub extend JobsScope with Debug::{to_repr}

///|
pub extend JobsScope with ToJson::{to_json}

///|
pub extend JobsScope with FromJson::{from_json}

///|
pub(all) struct JobsListPayload {
  scope : JobsScope
  offset : Int
} derive(Eq, Debug)

///|
pub impl FromJson for JobsListPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "JobsListPayload")
  let scope : JobsScope = @json.from_json(
    obj.required_json("scope"),
    path=path.add_key("scope"),
  )
  let offset : Int = {
    let n = jobs_uint(obj.required_json("offset"), path.add_key("offset"))
    guard n <= 2147483647L else {
      raise JsonDecodeError((path, "integer too large"))
    }
    n.to_int()
  }
  { scope, offset, }
}

///|
pub impl ToJson for JobsListPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["scope"] = self.scope.to_json()
  fields["offset"] = self.offset.to_json()
  fields.to_json()
}

///|
pub extend JobsListPayload with Eq::{equal, not_equal}

///|
pub extend JobsListPayload with Debug::{to_repr}

///|
pub extend JobsListPayload with ToJson::{to_json}

///|
pub extend JobsListPayload with FromJson::{from_json}

///|
pub(all) struct JobTarget {
  scope : JobsScope
  generation : String
  job_id : String
} derive(Eq, Debug)

///|
pub impl FromJson for JobTarget with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "JobTarget")
  let scope : JobsScope = @json.from_json(
    obj.required_json("scope"),
    path=path.add_key("scope"),
  )
  let generation : String = @json.from_json(
    obj.required_json("generation"),
    path=path.add_key("generation"),
  )
  let job_id : String = @json.from_json(
    obj.required_json("job_id"),
    path=path.add_key("job_id"),
  )
  guard @wire.valid_job_component(generation) &&
    @wire.valid_job_component(job_id) else {
    raise JsonDecodeError((path, "invalid job identity"))
  }
  { scope, generation, job_id, }
}

///|
pub impl ToJson for JobTarget with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["scope"] = self.scope.to_json()
  fields["generation"] = self.generation.to_json()
  fields["job_id"] = self.job_id.to_json()
  fields.to_json()
}

///|
pub extend JobTarget with Eq::{equal, not_equal}

///|
pub extend JobTarget with Debug::{to_repr}

///|
pub extend JobTarget with ToJson::{to_json}

///|
pub extend JobTarget with FromJson::{from_json}

///|
pub(all) struct JobReadPayload {
  target : JobTarget
  offset : Int64?
  limit : Int
} derive(Eq, Debug)

///|
pub impl FromJson for JobReadPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "JobReadPayload")
  let target : JobTarget = @json.from_json(
    obj.required_json("target"),
    path=path.add_key("target"),
  )
  let offset : Int64? = match obj.optional_json("offset") {
    None => None
    Some(value) => Some(jobs_uint(value, path.add_key("offset")))
  }
  let limit : Int = {
    let n = jobs_uint(obj.required_json("limit"), path.add_key("limit"))
    guard n <= 2147483647L else {
      raise JsonDecodeError((path, "integer too large"))
    }
    n.to_int()
  }
  guard limit >= 4 && limit <= 65536 else {
    raise JsonDecodeError((path, "log page limit must be 4..65536 bytes"))
  }
  { target, offset, limit, }
}

///|
pub impl ToJson for JobReadPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["target"] = self.target.to_json()
  if self.offset is Some(value) {
    fields["offset"] = value.to_double().to_json()
  }
  fields["limit"] = self.limit.to_json()
  fields.to_json()
}

///|
pub extend JobReadPayload with Eq::{equal, not_equal}

///|
pub extend JobReadPayload with Debug::{to_repr}

///|
pub extend JobReadPayload with ToJson::{to_json}

///|
pub extend JobReadPayload with FromJson::{from_json}

///|
pub(all) struct JobView {
  job : @wire.JobRecord
  output_path : String?
  controllable : Bool
  error : String?
} derive(Eq, Debug)

///|
pub impl FromJson for JobView with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "JobView")
  let job : @wire.JobRecord = @json.from_json(
    obj.required_json("job"),
    path=path.add_key("job"),
  )
  let output_path : String? = match obj.optional_json("output_path") {
    None => None
    Some(value) =>
      Some(@json.from_json(value, path=path.add_key("output_path")))
  }
  let controllable : Bool = @json.from_json(
    obj.required_json("controllable"),
    path=path.add_key("controllable"),
  )
  let error : String? = match obj.optional_json("error") {
    None => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("error")))
  }
  { job, output_path, controllable, error, }
}

///|
pub impl ToJson for JobView with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["job"] = self.job.to_json()
  if self.output_path is Some(value) {
    fields["output_path"] = value.to_json()
  }
  fields["controllable"] = self.controllable.to_json()
  if self.error is Some(value) {
    fields["error"] = value.to_json()
  }
  fields.to_json()
}

///|
pub extend JobView with Eq::{equal, not_equal}

///|
pub extend JobView with Debug::{to_repr}

///|
pub extend JobView with ToJson::{to_json}

///|
pub extend JobView with FromJson::{from_json}

///|
pub(all) struct JobsListReply {
  jobs : Array[JobView]
  next_offset : Int?
  errors : Array[String]
} derive(Eq, Debug)

///|
pub impl FromJson for JobsListReply with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "JobsListReply")
  let jobs : Array[JobView] = @json.from_json(
    obj.required_json("jobs"),
    path=path.add_key("jobs"),
  )
  let next_offset : Int? = match obj.optional_json("next_offset") {
    None => None
    Some(value) =>
      Some(
        {
          let n = jobs_uint(value, path.add_key("next_offset"))
          guard n <= 2147483647L else {
            raise JsonDecodeError((path, "integer too large"))
          }
          n.to_int()
        },
      )
  }
  let errors : Array[String] = @json.from_json(
    obj.required_json("errors"),
    path=path.add_key("errors"),
  )
  { jobs, next_offset, errors, }
}

///|
pub impl ToJson for JobsListReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["jobs"] = self.jobs.to_json()
  if self.next_offset is Some(value) {
    fields["next_offset"] = value.to_json()
  }
  fields["errors"] = self.errors.to_json()
  fields.to_json()
}

///|
pub extend JobsListReply with Eq::{equal, not_equal}

///|
pub extend JobsListReply with Debug::{to_repr}

///|
pub extend JobsListReply with ToJson::{to_json}

///|
pub extend JobsListReply with FromJson::{from_json}

///|
pub(all) struct JobReadReply {
  text : String
  start_offset : Int64
  next_offset : Int64
  size : Int64
  more : Bool
  output_path : String
} derive(Eq, Debug)

///|
pub impl FromJson for JobReadReply with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "JobReadReply")
  let text : String = @json.from_json(
    obj.required_json("text"),
    path=path.add_key("text"),
  )
  let start_offset : Int64 = jobs_uint(
    obj.required_json("start_offset"),
    path.add_key("start_offset"),
  )
  let next_offset : Int64 = jobs_uint(
    obj.required_json("next_offset"),
    path.add_key("next_offset"),
  )
  let size : Int64 = jobs_uint(obj.required_json("size"), path.add_key("size"))
  let more : Bool = @json.from_json(
    obj.required_json("more"),
    path=path.add_key("more"),
  )
  let output_path : String = @json.from_json(
    obj.required_json("output_path"),
    path=path.add_key("output_path"),
  )
  { text, start_offset, next_offset, size, more, output_path, }
}

///|
pub impl ToJson for JobReadReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["text"] = self.text.to_json()
  fields["start_offset"] = self.start_offset.to_double().to_json()
  fields["next_offset"] = self.next_offset.to_double().to_json()
  fields["size"] = self.size.to_double().to_json()
  fields["more"] = self.more.to_json()
  fields["output_path"] = self.output_path.to_json()
  fields.to_json()
}

///|
pub extend JobReadReply with Eq::{equal, not_equal}

///|
pub extend JobReadReply with Debug::{to_repr}

///|
pub extend JobReadReply with ToJson::{to_json}

///|
pub extend JobReadReply with FromJson::{from_json}

///|
pub(all) struct JobStopReply {
  outcome : @wire.JobStopOutcome
} derive(Eq, Debug)

///|
pub impl FromJson for JobStopReply with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "JobStopReply")
  let outcome : @wire.JobStopOutcome = @json.from_json(
    obj.required_json("outcome"),
    path=path.add_key("outcome"),
  )
  { outcome, }
}

///|
pub impl ToJson for JobStopReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["outcome"] = self.outcome.to_json()
  fields.to_json()
}

///|
pub extend JobStopReply with Eq::{equal, not_equal}

///|
pub extend JobStopReply with Debug::{to_repr}

///|
pub extend JobStopReply with ToJson::{to_json}

///|
pub extend JobStopReply with FromJson::{from_json}
