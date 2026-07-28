///|
// Lua 5.4 Interpreter - Formal API Specification
// This package defines the contract used by the Lua spec-driven tests.

///|
/// Errors raised by parsing or executing Lua code.
pub(all) suberror LuaError {
  SyntaxError(String)
  RuntimeError(String)
} derive(Show, Eq, ToJson)

///|
/// Execute a Lua chunk in a fresh VM with standard Lua 5.4 libraries loaded.
///
/// Required libraries for this suite: base, string, table, math, coroutine.
///
/// - Accepts UTF-8 source code.
/// - Raises SyntaxError on parse/compile failures.
/// - Raises RuntimeError on runtime errors.
declare pub fn exec(src : StringView) -> Unit raise LuaError
