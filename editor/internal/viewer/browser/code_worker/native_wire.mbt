///|
/// The wire remains ordinary JSON and is decoded by the closed protocol.
/// Native parsing avoids scanning every character of large fold/diff replies
/// on the UI thread; the visitor only constructs the typed JSON value tree.
pub fn parse_wire_json(input : String) -> Json raise {
  json_from_native(@js.Value::from_json_string(input))
}

///|
pub fn stringify_wire_json(value : Json) -> String raise {
  @js.Value::from_json(value).to_json_string()
}

///|
priv suberror InvalidNativeJson {
  InvalidNativeJson
}

///|
fn json_from_native(value : @js.Value) -> Json raise {
  match native_json_kind(value) {
    "null" => Json::null()
    "boolean" => Json::boolean(value.cast())
    "number" => Json::number(value.cast())
    "string" => Json::string(value.cast())
    "array" => {
      let length : Int = value.get_with_string("length")
      let values = Array::makei(length, index => {
        json_from_native(value.get_with_index(index))
      })
      Json::array(values)
    }
    "object" => {
      let values : Map[String, Json] = Map([])
      for key in native_json_keys(value) {
        values[key] = json_from_native(value.get_with_string(key))
      }
      Json::object(values)
    }
    _ => raise InvalidNativeJson
  }
}

///|
extern "js" fn native_json_kind(value : @js.Value) -> String =
  #| value => value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value

///|
extern "js" fn native_json_keys(value : @js.Value) -> FixedArray[String] = "Object.keys"
