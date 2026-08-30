///|
/// Minimal logger sink abstraction. Methods are `noraise` so logging cannot
/// fail a workflow. Dynamic trait dispatch is a live host-extension contract,
/// even though direct member references appear unused to the API analyzer.
pub(open) trait Logger {
  fn log(Self, LogEntry) -> Unit noraise
  fn flush(Self) -> Unit noraise
}

///|
/// Logger sink that drops every entry.
struct NullLogger {
  _unit : Unit
}

///|
/// Creates a sink that ignores logs and flushes.
pub fn NullLogger::NullLogger() -> NullLogger {
  { _unit: (), }
}

///|
/// Drops one log entry.
pub impl Logger for NullLogger with fn log(_self, _entry) {
  ()
}

///|
/// No-op flush for the null sink.
pub impl Logger for NullLogger with fn flush(_self) {
  ()
}

///|
/// Number of flush calls observed by the documented memory sink.
pub fn MemoryLogger::flush_count(self : MemoryLogger) -> Int {
  self.flush_count.val
}

///|
/// Records one log entry in memory.
pub impl Logger for MemoryLogger with fn log(self, entry) {
  self.entries.push(entry)
}

///|
/// Records a flush boundary in memory.
pub impl Logger for MemoryLogger with fn flush(self) {
  self.flush_count.val += 1
}

///|
/// Logger sink that fans each entry and flush to multiple sinks.
struct MultiplexLogger {
  loggers : Array[&Logger]
}

///|
/// Creates a logger fan-out over the supplied sinks.
pub fn MultiplexLogger::MultiplexLogger(
  loggers : Array[&Logger],
) -> MultiplexLogger {
  { loggers, }
}

///|
/// Emits one entry to every child logger.
pub impl Logger for MultiplexLogger with fn log(self, entry) {
  for logger in self.loggers {
    logger.log(entry)
  }
}

///|
/// Flushes every child logger.
pub impl Logger for MultiplexLogger with fn flush(self) {
  for logger in self.loggers {
    logger.flush()
  }
}

///|
/// Emits an already-structured log entry when it passes the threshold.
pub fn LogService::log(self : LogService, entry : LogEntry) -> Unit {
  if should_log(self.level, entry.level) {
    self.logger.log(entry)
  }
}

///|
/// Emits a trace-level entry.
pub fn LogService::trace(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Trace, category, message, details, })
}

///|
/// Emits a debug-level entry.
pub fn LogService::debug(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Debug, category, message, details, })
}

///|
/// Emits an info-level entry.
pub fn LogService::info(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Info, category, message, details, })
}

///|
/// Creates an empty in-memory sink for tests and harness diagnostics.
pub fn MemoryLogger::MemoryLogger() -> MemoryLogger {
  MemoryLogger::new_impl()
}

///|
/// Returns a snapshot of the collected entries.
pub fn MemoryLogger::entries(self : MemoryLogger) -> Array[LogEntry] {
  self.entries_impl()
}

///|
pub extend MemoryLogger with Logger::{flush, log}

///|
pub extend MultiplexLogger with Logger::{flush, log}

///|
pub extend NullLogger with Logger::{flush, log}
