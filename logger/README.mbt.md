# Logger

This package provides a tiny native-only async logger for OpenSeek. It wraps an
`@stdio.Output`, applies a minimum severity level, and exposes `<+`-compatible
sinks.

## API Shape

- `Level`: `TRACE`, `DEBUG`, `INFO`, `WARN`, and `ERROR`.
- `stdout(min_level?)`: build a stdout logger.
- `Logger::at(level)`: get `Some(LogSink)` when `level` is enabled, otherwise
  `None`.
- `Logger::trace/debug/info/warn/error()`: convenience optional sinks.
- `LogSink` supports `<+` and can write JSON object lines with
  `write_object(Map[String, String])`.

```moonbit check
///|
test "logger filters by severity" {
  let logger = @logger.Logger(@stdio.stdout, min_level=WARN)
  assert_false(logger.enabled(INFO))
  assert_true(logger.enabled(ERROR))
  assert_true(logger.debug() is None)
  assert_true(logger.error() is Some(_))
}
```
