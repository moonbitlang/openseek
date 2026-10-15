///|
/// Page the host's conversation inventory before it reaches an
/// agent's bounded tool output. Null/missing options select their defaults.
pub struct ListPage {
  offset : Int32
  limit : Int32
}

///|
pub impl FromJson for ListPage with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise @json.JsonDecodeError(
      (path, "session list arguments must be an object"),
    )
  }
  fn integer(
    key : String,
    fallback : Int32,
  ) -> Int32 raise @json.JsonDecodeError {
    match fields.get(key) {
      None | Some(Null) => fallback
      Some(value) => {
        let decoded : Int32 = @json.from_json(value, path=path.add_key(key))
        guard value is Number(number, ..) && number == decoded.to_double() else {
          raise @json.JsonDecodeError(
            (path.add_key(key), "expected an integer"),
          )
        }
        decoded
      }
    }
  }
  let offset = integer("offset", 0)
  let limit = integer("limit", 20)
  guard offset >= 0 && limit >= 1 && limit <= 50 else {
    raise @json.JsonDecodeError(
      (path, "offset must be nonnegative; limit must be between 1 and 50"),
    )
  }
  { offset, limit, }
}

///|
pub extend ListPage with FromJson::{from_json}

///|
pub fn ListPage::page(
  self : ListPage,
  inventory : @protocol.SessionsReply,
) -> Json raise {
  let candidates : Array[Json] = []
  for group in inventory.groups {
    // An unavailable store cannot be represented as an empty successful page.
    if !group.error.is_empty() {
      fail("Cannot list conversations in \{group.workspace}: \{group.error}")
    }
    for session in group.sessions {
      candidates.push({
        "id": session.id,
        "title": session.title.map_or(Json::null(), title => Json(title)),
        "workspace": group.workspace,
      })
    }
  }
  let sessions : Array[Json] = []
  let mut index = self.offset
  // Reserve ample room for the envelope below the MCP bridge's 50k cap.
  // Measure serialized data: escaping can make short-looking titles large.
  let mut size = 100
  while index < candidates.length() && sessions.length() < self.limit {
    let row = candidates[index]
    let row_size = row.stringify().length() + 1
    if size + row_size > 32000 {
      if sessions.is_empty() {
        fail(
          "A conversation entry exceeds the 32000-character list page budget",
        )
      }
      break
    }
    sessions.push(row)
    size += row_size
    index += 1
  }
  {
    "sessions": sessions,
    "next_offset": if index < candidates.length() {
      Json(index)
    } else {
      Json::null()
    },
  }
}
