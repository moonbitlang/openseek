///|
/// The JSON record for one log entry.
///
/// Keys are `timestamp`, `level`, `category` (when given) and `source`,
/// followed by the caller's fields; a field wins on a name clash. This is the
/// record `tonyfettes/xlog` wrote, which `openseek-desktop.log` readers rely
/// on.
fn record(
  level~ : Level,
  category~ : String?,
  timestamp_ms~ : UInt64,
  source~ : SourceLoc,
  fields~ : Map[String, Json],
) -> Json {
  let object : Map[String, Json] = {
    "timestamp": format_timestamp(timestamp_ms),
    "level": level.to_string(),
  }
  if category is Some(category) {
    object["category"] = Json::string(category)
  }
  object["source"] = Json::string(source.to_string())
  for key, value in fields {
    object[key] = value
  }
  Json::object(object)
}

///|
/// Format milliseconds since the Unix epoch as an RFC 3339 UTC timestamp
/// with millisecond precision, e.g. `2026-11-04T13:58:19.202Z`.
fn format_timestamp(ms : UInt64) -> String {
  let ms = ms.reinterpret_as_int64()
  let millis = (ms % 1000L).to_int()
  let seconds = ms / 1000L
  let second_of_day = (seconds % 86400L).to_int()
  // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
  let z = seconds / 86400L + 719468L
  let era = z / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = (doy - (153L * mp + 2L) / 5L + 1L).to_int()
  let month = (if mp < 10L { mp + 3L } else { mp - 9L }).to_int()
  let year = (yoe + era * 400L + (if month <= 2 { 1L } else { 0L })).to_int()
  let date = "\{pad(year, 4)}-\{pad(month, 2)}-\{pad(day, 2)}"
  let hour = pad(second_of_day / 3600, 2)
  let minute = pad(second_of_day / 60 % 60, 2)
  let second = pad(second_of_day % 60, 2)
  "\{date}T\{hour}:\{minute}:\{second}.\{pad(millis, 3)}Z"
}

///|
fn pad(value : Int32, width : Int32) -> String {
  value.to_string().pad_start(width, '0')
}
