///|
/// Process-wide structured logging adapter, installed by the embedding host.
/// Service packages produce events without depending on a native log backend.
pub(all) enum Level {
  Debug
  Info
  Warn
  Error
}

///|
let sink : Ref[((Level, String?, SourceLoc, Json) -> Unit)?] = Ref(None)

///|
pub fn install(writer : (Level, String?, SourceLoc, Json) -> Unit) -> Unit {
  sink.val = Some(writer)
}

///|
struct Event {
  fields : Map[String, Json]
  finish : (Json) -> Unit
}

///|
fn event(level : Level, category : String?, loc : SourceLoc) -> Event? {
  sink.val.map(writer => {
    fields: Map([]),
    finish: fields => writer(level, category, loc, fields),
  })
}

///|
#callsite(autofill(loc))
pub fn debug(category? : String, loc~ : SourceLoc) -> Event? {
  event(Debug, category, loc)
}

///|
#callsite(autofill(loc))
pub fn info(category? : String, loc~ : SourceLoc) -> Event? {
  event(Info, category, loc)
}

///|
#callsite(autofill(loc))
pub fn warn(category? : String, loc~ : SourceLoc) -> Event? {
  event(Warn, category, loc)
}

///|
#callsite(autofill(loc))
pub fn error(category? : String, loc~ : SourceLoc) -> Event? {
  event(Error, category, loc)
}

///|
pub fn Event::write_object_begin(_ : Event) -> Unit {
  ()
}

///|
pub fn[T : ToJson] Event::write_object_field(
  self : Event,
  key : String,
  value : T,
) -> Unit {
  self.fields[key] = value.to_json()
}

///|
pub fn Event::write_object_end(self : Event) -> Unit {
  (self.finish)(Json(self.fields))
}
