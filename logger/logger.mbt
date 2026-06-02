///|
/// Logging severity. Higher levels include fewer records when used as a
/// logger's `min_level`.
pub(all) enum Level {
  TRACE
  DEBUG
  INFO
  WARN
  ERROR
}

///|
pub fn Level::rank(self : Level) -> Int {
  match self {
    TRACE => 0
    DEBUG => 1
    INFO => 2
    WARN => 3
    ERROR => 4
  }
}

///|
pub fn Level::label(self : Level) -> String {
  match self {
    TRACE => "TRACE"
    DEBUG => "DEBUG"
    INFO => "INFO"
    WARN => "WARN"
    ERROR => "ERROR"
  }
}

///|
pub struct Logger {
  priv output : @stdio.Output
  priv min_level : Level
}

///|
pub fn Logger::Logger(
  output : @stdio.Output,
  min_level? : Level = INFO,
) -> Logger {
  { output, min_level }
}

///|
pub fn stdout(min_level? : Level = INFO) -> Logger {
  Logger(@stdio.stdout, min_level~)
}

///|
pub fn Logger::enabled(self : Logger, level : Level) -> Bool {
  level.rank() >= self.min_level.rank()
}

///|
pub fn Logger::at(self : Logger, level : Level) -> LogSink? {
  if self.enabled(level) {
    Some({ output: self.output })
  } else {
    None
  }
}

///|
pub fn Logger::trace(self : Logger) -> LogSink? {
  self.at(TRACE)
}

///|
pub fn Logger::debug(self : Logger) -> LogSink? {
  self.at(DEBUG)
}

///|
pub fn Logger::info(self : Logger) -> LogSink? {
  self.at(INFO)
}

///|
pub fn Logger::warn(self : Logger) -> LogSink? {
  self.at(WARN)
}

///|
pub fn Logger::error(self : Logger) -> LogSink? {
  self.at(ERROR)
}

///|
pub struct LogSink {
  priv output : @stdio.Output
}

///|
pub async fn LogSink::write_string(self : LogSink, text : String) -> Unit {
  self.output.write(text)
}

///|
pub async fn[A : Show] LogSink::write(self : LogSink, value : A) -> Unit {
  self.write_string(value.to_string())
}

///|
pub async fn LogSink::write_object(
  self : LogSink,
  fields : Map[String, String],
) -> Unit {
  let object : Map[String, Json] = Map([])
  for key, value in fields {
    object.set(key, Json::string(value))
  }
  self.write_string(Json::object(object).stringify() + "\n")
}

///|
test "level ranks follow severity order" {
  assert_true(TRACE.rank() < DEBUG.rank())
  assert_true(DEBUG.rank() < INFO.rank())
  assert_true(INFO.rank() < WARN.rank())
  assert_true(WARN.rank() < ERROR.rank())
}

///|
test "level labels are uppercase" {
  assert_eq(TRACE.label(), "TRACE")
  assert_eq(DEBUG.label(), "DEBUG")
  assert_eq(INFO.label(), "INFO")
  assert_eq(WARN.label(), "WARN")
  assert_eq(ERROR.label(), "ERROR")
}

///|
test "logger filters below the minimum level" {
  let logger = Logger(@stdio.stdout, min_level=WARN)
  assert_false(logger.enabled(TRACE))
  assert_false(logger.enabled(DEBUG))
  assert_false(logger.enabled(INFO))
  assert_true(logger.enabled(WARN))
  assert_true(logger.enabled(ERROR))
  assert_true(logger.info() is None)
  assert_true(logger.error() is Some(_))
}

///|
test "logger level helpers return optional sinks" {
  let logger = Logger(@stdio.stdout, min_level=INFO)
  assert_true(logger.debug() is None)
  assert_true(logger.info() is Some(_))
}
