///|
/// Project only known durable content fields. Unknown records remain untouched
/// and no image data is decoded, cached, or copied into the desktop snapshot.
fn project_images(
  json : Json,
  record : String,
  offset : Int64,
  length : Int32,
) -> Json raise RecordError {
  guard json is Object(event) &&
    event.get("sequence") is Some(Number(sequence, ..)) &&
    event.get("item") is Some(Object(item)) &&
    item.get("kind") is Some(String("user" | "tool_result")) &&
    item.get("payload") is Some(Object(payload)) &&
    payload.get("content") is Some(Array(parts)) else {
    return json
  }
  for part in parts {
    if part is { "type": "image_ref", .. } {
      raise Unreadable(
        "image references are desktop projections, not durable content",
      )
    }
  }
  let content : Array[Json] = parts.mapi((part, value) => {
    if value
      is { "type": "image", "media_type": String(_), "data": String(_), .. } {
      let image : @protocol.SessionImageRef = {
        record,
        offset,
        length,
        sequence: sequence.to_int(),
        part,
      }
      { "type": "image_ref", "image": image.to_json() }
    } else {
      value
    }
  })
  let payload = payload.copy()
  payload["content"] = Json(content)
  let item = item.copy()
  item["payload"] = Json(payload)
  let event = event.copy()
  event["item"] = Json(item)
  Json(event)
}

///|
/// Fetch just the referenced event, under the same shared lock as snapshots.
/// Event identity and bounds reject stale ranges after a rewrite. Decode and
/// validate only the requested image, preserving the engine's raster checks.
pub async fn read_image(
  image : @protocol.SessionImageRef,
) -> @protocol.SessionImageReply {
  guard @pathx.Absolute::from_uri_path(image.record) is Some(record) else {
    raise Unreadable("session image record must be an absolute path")
  }
  guard image.offset >= 0 &&
    image.length > 0 &&
    image.sequence > 0 &&
    image.part >= 0 else {
    raise Unreadable("invalid session image range")
  }
  with_shared_record_lock(record.to_path().dirname().join("session.lock"), () => {
    let file = @fs.open(record.to_string(), mode=ReadOnly)
    defer file.close()
    let size = file.size()
    guard image.offset <= size && image.length.to_int64() <= size - image.offset else {
      raise Unreadable("session image record changed; reload the conversation")
    }
    let bytes = file.read_exactly_at(image.length, position=image.offset)
    let json = @json.parse(@utf8.decode(bytes))
    guard json
      is {
        "sequence": Number(sequence, ..),
        "item": {
          "kind": String("user" | "tool_result"),
          "payload": { "content": Array(parts), .. },
          ..
        },
        ..
      } &&
      sequence == image.sequence.to_double() &&
      parts.get(image.part) is Some(part) else {
      raise Unreadable("session image record changed; reload the conversation")
    }
    let part : @wire.ContentPart = @json.from_json(part)
    guard part is Image(image) else {
      raise Unreadable("referenced content is not an image")
    }
    { data_url: image.data_url(), }
  })
}
