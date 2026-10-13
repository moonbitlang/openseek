///|
/// A byte range in a durable record, plus the event and content-part identity
/// checked when reading it. Appends leave references valid; a compaction that
/// relocates the event makes the reference fail rather than select another row.
pub(all) struct SessionImageRef {
  record : String
  offset : Int64
  length : Int32
  sequence : Int32
  part : Int32
} derive(Debug, Eq, Hash)

///|
pub impl ToJson for SessionImageRef with fn to_json(self) {
  {
    "record": self.record,
    "offset": self.offset,
    "length": self.length,
    "sequence": self.sequence,
    "part": self.part,
  }
}

///|
pub impl FromJson for SessionImageRef with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "session image reference")
  let record = obj.required_string("record")
  let offset : Int64 = @json.from_json(
    obj.required_json("offset"),
    path=path.add_key("offset"),
  )
  let length = obj.required_int("length")
  let sequence = obj.required_int("sequence")
  let part = obj.required_int("part")
  guard !record.is_blank() &&
    offset >= 0 &&
    length > 0 &&
    sequence > 0 &&
    part >= 0 else {
    raise JsonDecodeError((path, "invalid session image range"))
  }
  { record, offset, length, sequence, part, }
}

///|
/// Desktop display content. The durable engine format still embeds images;
/// host snapshots replace them with references before decoding their bytes.
pub(all) struct SessionContent(Array[SessionContentPart]) derive(Debug, Eq)

///|
pub(all) enum SessionContentPart {
  Text(String)
  Image(@wire.Image)
  ImageRef(SessionImageRef)
} derive(Debug, Eq)

///|
pub impl ToJson for SessionContent with fn to_json(self) {
  if self.0 is [Text(text)] {
    return Json(text)
  }
  let parts : Array[Json] = self.0.map(part => {
    match part {
      Text(text) => { "type": "text", "text": text }
      Image(image) =>
        {
          "type": "image",
          "media_type": image.media_type,
          "data": @base64.encode(image.bytes),
        }
      ImageRef(image) => { "type": "image_ref", "image": image.to_json() }
    }
  })
  Json(parts)
}

///|
pub impl FromJson for SessionContent with fn from_json(json, path) {
  if json is String(text) {
    return SessionContent([Text(text)])
  }
  guard json is Array(parts) else {
    raise JsonDecodeError((path, "expected session content"))
  }
  SessionContent(
    parts.mapi((index, part) => {
      if part is { "type": "image_ref", "image": image, .. } {
        ImageRef(
          @json.from_json(image, path=path.add_index(index).add_key("image")),
        )
      } else {
        let part : @wire.ContentPart = @json.from_json(
          part,
          path=path.add_index(index),
        )
        match part {
          Text(text) => Text(text)
          Image(image) => Image(image)
        }
      }
    }),
  )
}

///|
pub(all) struct SessionImageReply {
  data_url : String
} derive(Debug, Eq)

///|
pub impl ToJson for SessionImageReply with fn to_json(self) {
  { "data_url": self.data_url }
}

///|
pub impl FromJson for SessionImageReply with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "session image reply")
  { data_url: obj.required_string("data_url"), }
}

///|
pub extend SessionImageRef with Debug::{to_repr}

///|
pub extend SessionImageRef with Eq::{equal, not_equal}

///|
pub extend SessionImageRef with ToJson::{to_json}

///|
pub extend SessionImageRef with @json.FromJson::{from_json}

///|
pub extend SessionContent with Debug::{to_repr}

///|
pub extend SessionContent with Eq::{equal, not_equal}

///|
pub extend SessionContent with ToJson::{to_json}

///|
pub extend SessionContent with @json.FromJson::{from_json}

///|
pub extend SessionContentPart with Debug::{to_repr}

///|
pub extend SessionContentPart with Eq::{equal, not_equal}

///|
pub extend SessionImageReply with Debug::{to_repr}

///|
pub extend SessionImageReply with Eq::{equal, not_equal}

///|
pub extend SessionImageReply with ToJson::{to_json}

///|
pub extend SessionImageReply with @json.FromJson::{from_json}

///|
pub extend SessionImageRef with Hash::{hash, hash_combine}

///|
pub fn SessionContent::text(self : SessionContent) -> String {
  self.0
  .iter()
  .filter_map(part => {
    match part {
      Text(text) => Some(text)
      _ => None
    }
  })
  .join("")
}
