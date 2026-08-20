///|
/// Log threshold and entry severity. `Off` disables emission.
pub(all) enum LogLevel {
  Off
  Trace
  Debug
  Info
  Warning
  Error
} derive(Eq, Debug)

///|
/// Structured log event emitted by app and viewer services.
pub(all) struct LogEntry {
  level : LogLevel
  category : String
  message : String
  details : Array[(String, String)]
} derive(Eq, Debug)

///|
/// In-memory logger used by tests and harness-facing diagnostics.
struct MemoryLogger {
  entries : Array[LogEntry]
  flush_count : Ref[Int]
}

///|
/// Creates an empty in-memory log sink.
fn MemoryLogger::new_impl() -> MemoryLogger {
  { entries: [], flush_count: Ref(0) }
}

///|
/// Snapshot of collected log entries.
fn MemoryLogger::entries_impl(self : MemoryLogger) -> Array[LogEntry] {
  self.entries.copy()
}

///|
/// Thresholded logging facade used by services that should not know the sink
/// implementation.
struct LogService {
  level : LogLevel
  logger : &Logger
}

///|
/// Opaque logging capability passed across public service boundaries. It
/// exposes only the warning and error operations consumed by Viewer runtime
/// code and does not reveal the concrete sink or threshold policy.
struct LogHandle {
  warn_callback : (String, String, Array[(String, String)]) -> Unit
  error_callback : (String, String, Array[(String, String)]) -> Unit
}

///|
/// Creates a log service with an optional threshold and sink.
fn LogService::new_impl(
  level? : LogLevel = Info,
  logger? : &Logger = NullLogger(),
) -> LogService {
  { level, logger }
}

///|
/// Creates a thresholded logging service.
pub fn LogService::LogService(
  level? : LogLevel = Info,
  logger? : &Logger = NullLogger(),
) -> LogService {
  LogService::new_impl(level~, logger~)
}

///|
/// Derives the minimal Viewer logging capability from this concrete service.
/// The handle borrows behavior through callbacks; it owns neither the service
/// nor its logger.
pub fn LogService::log_handle(self : LogService) -> LogHandle {
  {
    warn_callback: (category, message, details) => {
      self.warn(category, message, details~)
    },
    error_callback: (category, message, details) => {
      self.error(category, message, details~)
    },
  }
}

///|
/// Emits a warning through the captured logging capability.
pub fn LogHandle::warn(
  self : LogHandle,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  (self.warn_callback)(category, message, details)
}

///|
/// Emits a warning-level entry.
pub fn LogService::warn(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Warning, category, message, details })
}

///|
/// Emits an error through the captured logging capability.
fn LogHandle::error_impl(
  self : LogHandle,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  (self.error_callback)(category, message, details)
}

///|
/// Emits an error through the narrowed Viewer logging handle.
pub fn LogHandle::error(
  self : LogHandle,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.error_impl(category, message, details~)
}

///|
/// Emits an error-level entry.
fn LogService::error_impl(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Error, category, message, details })
}

///|
/// Emits an error-level entry.
pub fn LogService::error(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.error_impl(category, message, details~)
}

///|
/// Flushes the configured log sink.
fn LogService::flush_impl(self : LogService) -> Unit {
  self.logger.flush()
}

///|
/// Flushes the configured sink.
pub fn LogService::flush(self : LogService) -> Unit {
  self.flush_impl()
}

///|
/// Stable lowercase label for configuration and diagnostics.
fn LogLevel::label_impl(self : LogLevel) -> String {
  match self {
    Off => "off"
    Trace => "trace"
    Debug => "debug"
    Info => "info"
    Warning => "warning"
    Error => "error"
  }
}

///|
/// Stable lowercase label for configuration and diagnostics.
pub fn LogLevel::label(self : LogLevel) -> String {
  self.label_impl()
}

///|
/// Whether the level should be treated as a failure signal by harness checks.
fn LogLevel::is_warning_or_error_impl(self : LogLevel) -> Bool {
  level_rank(self) >= level_rank(Warning) && self != Off
}

///|
/// Whether this level is warning-or-error severity.
pub fn LogLevel::is_warning_or_error(self : LogLevel) -> Bool {
  self.is_warning_or_error_impl()
}

///|
fn should_log(configured : LogLevel, entry : LogLevel) -> Bool {
  configured != Off &&
  entry != Off &&
  level_rank(entry) >= level_rank(configured)
}

///|
fn level_rank(level : LogLevel) -> Int {
  match level {
    Off => 99
    Trace => 0
    Debug => 1
    Info => 2
    Warning => 3
    Error => 4
  }
}

///|
pub extend LogEntry with Debug::{to_repr}

///|
pub extend LogEntry with Eq::{equal, not_equal}

///|
pub extend LogLevel with Debug::{to_repr}

///|
pub extend LogLevel with Eq::{equal, not_equal}
