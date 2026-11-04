///|
/// Log levels ordered from most severe to most verbose.
///
/// A record is emitted when its level is less than or equal to the effective
/// level of its category.
#derive(Eq, Compare)
pub(all) enum Level {
  /// A fatal failure.
  Fatal
  /// An error that should be investigated.
  Error
  /// A warning about a degraded or unexpected condition.
  Warn
  /// General operational information.
  Info
  /// Detailed diagnostic information.
  Debug
  /// Very verbose diagnostic information.
  Trace
}

///|
pub extend Level with Eq::{equal, not_equal}

///|
pub extend Level with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub impl Show for Level with fn to_string(self) -> String {
  match self {
    Fatal => "FATAL"
    Error => "ERROR"
    Warn => "WARN"
    Info => "INFO"
    Debug => "DEBUG"
    Trace => "TRACE"
  }
}

///|
pub impl Show for Level with fn output(self, logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
pub extend Level with Show::{to_string, output}

///|
/// Parse a level name case-insensitively, as `MOON_XLOG` spells it.
fn parse_level(name : StringView) -> Level? {
  match name {
    ['F' | 'f', 'A' | 'a', 'T' | 't', 'A' | 'a', 'L' | 'l'] => Some(Fatal)
    ['E' | 'e', 'R' | 'r', 'R' | 'r', 'O' | 'o', 'R' | 'r'] => Some(Error)
    ['W' | 'w', 'A' | 'a', 'R' | 'r', 'N' | 'n'] => Some(Warn)
    ['I' | 'i', 'N' | 'n', 'F' | 'f', 'O' | 'o'] => Some(Info)
    ['D' | 'd', 'E' | 'e', 'B' | 'b', 'U' | 'u', 'G' | 'g'] => Some(Debug)
    ['T' | 't', 'R' | 'r', 'A' | 'a', 'C' | 'c', 'E' | 'e'] => Some(Trace)
    _ => None
  }
}
