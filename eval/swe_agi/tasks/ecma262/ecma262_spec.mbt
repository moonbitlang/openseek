///|
/// ECMA-262 JavaScript Interpreter - API Specification
///
/// This file contains declaration-only stubs that define the public API contract.
/// Implementations should provide these functions in separate files.

///|
/// Evaluate a JavaScript expression and return its string representation.
///
/// Parameters:
///
/// - expr: String containing a JavaScript expression
///
/// Returns the string representation of the evaluated value, matching
/// the output format of Node.js console (e.g. "42", "\"hello\"", "true", "NaN", etc.)
///
/// Example:
///
/// ```moonbit nocheck
/// let result = eval_expr("1 + 2")
/// // result == "3"
/// ```
declare pub fn eval_expr(expr : String) -> String
