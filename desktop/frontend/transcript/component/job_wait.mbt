///|
/// Keep the selected jobs visible even when the arguments disclosure is shut.
/// Pending is already part of the normal tool lifecycle; no new run state.
fn pending_job_wait_label(
  call : @transcript.ToolCall,
  descriptions? : Map[String, String] = Map([]),
  minimal? : Bool = false,
) -> String? {
  guard call.name == "job_wait" &&
    call.outcome is Pending(..) &&
    call.arguments is Some(arguments) else {
    return None
  }
  let args = @json.parse(arguments) catch { _ => return None }
  guard args is { "job_ids": Array(values), .. } && !values.is_empty() else {
    return None
  }
  let ids : Array[String] = []
  for value in values {
    guard value is String(id) && !id.is_blank() else { return None }
    if !ids.contains(id) {
      ids.push(id)
    }
  }
  if minimal {
    // Waiting can end when any target finishes (or user input arrives). This
    // names the current wait, never claims that every selected job is done.
    let targets = ids.map(id => {
      if descriptions.get(id) is Some(description) {
        "\"\{description}\""
      } else {
        id
      }
    })
    return Some(
      if targets.length() == 1 {
        "Wait for job \{targets[0]} to complete"
      } else {
        "Wait for any of these jobs to complete: \{targets.join(", ")}"
      },
    )
  }
  let targets = ids.map(id => {
    match descriptions.get(id) {
      Some(description) => "\{id}: \{description}"
      None => id
    }
  })
  Some("Waiting for \{targets.join(", ")}")
}

///|
/// Read only tool metadata, never command output. The map belongs to one
/// transcript render, so identical job IDs in other sessions cannot leak in.
fn collect_job_description(
  call : @transcript.ToolCall,
  descriptions : Map[String, String],
) -> Unit {
  guard (call.name == "mbtx" || call.name == "job_output") &&
    call.outcome is Done(is_error=false, brief=Some(brief), ..) &&
    call.arguments is Some(arguments) else {
    return
  }
  if call.name == "mbtx" {
    guard brief.strip_prefix("mbtx → bg ") is Some(id) && !id.is_blank() else {
      return
    }
    let args = @json.parse(arguments) catch { _ => return }
    guard args is { "description": String(description), .. } &&
      !description.is_blank() else {
      return
    }
    descriptions[id.to_owned()] = description
  } else if call.name == "job_output" {
    let args = @json.parse(arguments) catch { _ => return }
    guard args is { "job_id": String(id), .. } &&
      brief.strip_prefix("job \{id} (") is Some(rest) &&
      rest.split_once("): ") is Some((_, description)) &&
      !description.is_blank() else {
      return
    }
    descriptions[id] = description.to_owned()
  }
}

///|
fn job_wait_labels(
  item : @transcript.TranscriptItem,
  descriptions : Map[String, String],
) -> Map[Int, String] {
  let labels : Map[Int, String] = Map([])
  if item.kind is Assistant(calls~, ..) {
    for call in calls {
      collect_job_description(call, descriptions)
    }
    for index, call in calls {
      if pending_job_wait_label(call, descriptions~) is Some(label) {
        labels[index] = label
      }
    }
  }
  labels
}
