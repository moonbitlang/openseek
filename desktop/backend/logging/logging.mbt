///|
/// Process-wide logging state.
priv struct State {
  config : Config
  mut sink : (Json) -> Unit raise
}

///|
/// The environment variable read once at startup for the initial levels.
///
/// The name is kept from `tonyfettes/xlog` so existing `MOON_XLOG=debug`
/// habits keep working.
const LEVEL_ENV = "MOON_XLOG"

///|
let state : State = {
  config: @env.get_env_var(LEVEL_ENV)
  .bind(spec => Config::parse(spec, level=Info))
  .unwrap_or({ level: Info, levels: Map([]), }),
  // The default sink: one JSON object per line on standard output.
  sink: record => println(record.stringify()),
}

///|
/// Replace the sink that receives every emitted record.
///
/// Errors raised by the sink are ignored so logging never interrupts the
/// caller.
pub fn set_sink(sink : (Json) -> Unit raise) -> Unit {
  state.sink = sink
}

///|
/// Set the root level. Category overrides from `MOON_XLOG` still take
/// precedence for matching categories.
pub fn set_level(level : Level) -> Unit {
  state.config.level = level
}

///|
/// A log record being written field by field.
///
/// Level functions return an `Event` only when the level is enabled; write it
/// with `<?`, e.g. `@logging.info() <? { "message": "start" }`.
struct Event {
  level : Level
  category : String?
  timestamp_ms : UInt64
  source : SourceLoc
  fields : Map[String, Json]
}

///|
/// Begin the record's structured fields.
pub fn Event::write_object_begin(self : Event) -> Unit {
  self.fields.clear()
}

///|
/// Write one structured field.
pub fn[T : ToJson] Event::write_object_field(
  self : Event,
  key : String,
  value : T,
) -> Unit {
  self.fields[key] = value.to_json()
}

///|
/// Finish the record and hand it to the sink.
pub fn Event::write_object_end(self : Event) -> Unit {
  let record = record(
    level=self.level,
    category=self.category,
    timestamp_ms=self.timestamp_ms,
    source=self.source,
    fields=self.fields,
  )
  (state.sink)(record) catch {
    _ => ()
  }
}

///|
fn event(level : Level, category : String?, loc : SourceLoc) -> Event? {
  guard level <= state.config.effective_level(category) else { None }
  Some({
    level,
    category,
    timestamp_ms: @env.now(),
    source: loc,
    fields: Map([]),
  })
}

///|
/// Start an `Error` record if it is enabled.
#callsite(autofill(loc))
pub fn error(category? : String, loc~ : SourceLoc) -> Event? {
  event(Error, category, loc)
}

///|
/// Start a `Warn` record if it is enabled.
#callsite(autofill(loc))
pub fn warn(category? : String, loc~ : SourceLoc) -> Event? {
  event(Warn, category, loc)
}

///|
/// Start an `Info` record if it is enabled.
#callsite(autofill(loc))
pub fn info(category? : String, loc~ : SourceLoc) -> Event? {
  event(Info, category, loc)
}

///|
/// Start a `Debug` record if it is enabled.
#callsite(autofill(loc))
pub fn debug(category? : String, loc~ : SourceLoc) -> Event? {
  event(Debug, category, loc)
}
