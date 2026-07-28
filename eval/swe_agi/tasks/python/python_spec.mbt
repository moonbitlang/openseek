///|
// Python Interpreter - Formal API Specification
//
// This package defines a contract-first API for a Python (CPython-compatible)
// interpreter in MoonBit. The accompanying tests are derived from CPython's
// official regression tests under `Lib/test/` (curated subset).

///|
/// Python exception type for all runtime and syntax failures in this suite.
pub(all) suberror PyError {
  SyntaxError(String)
  NameError(String)
  TypeError(String)
  ValueError(String)
  ZeroDivisionError
  IndexError(String)
  KeyError(String)
  AttributeError(String)
  IoError(String)
  NotImplemented(String)
} derive(Show, Eq, ToJson)

///|
/// Opaque interpreter instance with its own globals/builtins state.
declare pub type Vm

///|
/// Opaque runtime value produced by evaluation.
declare pub type Value

///|
/// Create a fresh Python VM with standard builtins.
declare pub fn Vm::new() -> Vm

///|
/// Execute Python source code in "exec" mode.
///
/// - Must support multi-line modules with indentation.
/// - Mutations to globals must persist in the VM.
/// - Raises `PyError::SyntaxError` on invalid syntax.
/// - Raises `PyError::*` on runtime failures.
declare pub fn Vm::exec(self : Vm, src : StringView) -> Unit raise PyError

///|
/// Execute a full program (module-style) and return the value of the last
/// expression statement if present, otherwise return `None`.
///
/// This is a testing-oriented convenience API that allows generated tests to
/// execute a multi-statement snippet and still observe a result value.
declare pub fn Vm::exec_program(
  self : Vm,
  src : StringView,
) -> Value raise PyError

///|
/// Evaluate a Python expression in "eval" mode.
///
/// - Evaluates within the VM's current globals/builtins.
/// - Raises `PyError::SyntaxError` on invalid syntax.
/// - Raises `PyError::*` on runtime failures.
declare pub fn Vm::eval_expr(
  self : Vm,
  expr : StringView,
) -> Value raise PyError

///|
/// Convenience helper: evaluate an expression in a fresh VM.
declare pub fn eval_expr(expr : StringView) -> Value raise PyError

///|
/// Convenience helper: execute a program in a fresh VM and return the last
/// expression statement value (or `None`).
declare pub fn exec_program(src : StringView) -> Value raise PyError

///|
/// Read a UTF-8 file and execute it in the VM (module mode).
///
/// Notes:
/// - The `path` is resolved by the host; tests should use repo-relative paths
///   within the suite directory (e.g. `reference_pub_test/test_foo.py`).
/// - Any IO failure must raise `PyError::IoError`.
declare pub fn Vm::run_file(self : Vm, path : String) -> Unit raise PyError

///|
/// Convenience helper: run a file in a fresh VM.
declare pub fn run_file(path : String) -> Unit raise PyError

///|
/// Check that the given source parses under the given compilation mode without
/// executing it.
///
/// Supported modes: `"exec"` and `"eval"`.
///
/// Raises `PyError::SyntaxError` on parse error.
declare pub fn check_syntax(
  src : StringView,
  mode : String,
) -> Unit raise PyError

///|
/// Read a file (UTF-8) and check it parses in `"exec"` mode.
declare pub fn check_syntax_file(path : String) -> Unit raise PyError

///|
/// Convert a value to CPython-like `repr()` text.
declare pub fn Value::repr(self : Value) -> String

///|
/// Convert a value to CPython-like `str()` text.
declare pub fn Value::str(self : Value) -> String

///|
/// JSON encoding for test validation.
///
/// The JSON encoding must be stable and deterministic. For integers, encode the
/// value as a string to avoid host integer-size differences.
///
/// Required shapes:
///
/// - None: `{"type": "none"}`
/// - Bool: `{"type": "bool", "value": true|false}`
/// - Int: `{"type": "int", "value": "<decimal>"}`
/// - Str:
///   - `{"type": "str", "escape": "<unicode_escape>"}` where `<unicode_escape>`
///     is Python-style `unicode_escape` encoding without surrounding quotes
///     (e.g. `"\\n"`, `"\\udc80"`, `"\\U0001f600"`).
///   - This representation is required because CPython tests sometimes use
///     surrogate code points which are not valid UTF-8.
/// - Ellipsis: `{"type": "ellipsis"}`
/// - Tuple/List: `{"type": "tuple"|"list", "items": [<value-json>...]}`
/// - Dict: `{"type": "dict", "items": [[<key-json>, <value-json>]...]}`
///   (preserve insertion order)
declare pub fn Value::to_test_json(self : Value) -> Json
