///|
// R6RS Scheme Interpreter - Formal API Specification
// This file contains declaration-only stubs that define the public API contract.
// Implementations should provide these types and functions in separate files.

///|
/// Runtime values produced by evaluation
declare pub type Value

///|
/// Evaluates a Scheme program and returns the value of the last form
///
/// Parameters:
///
/// - src: String containing Scheme source code
///
/// Returns the Value produced by evaluating the last form
///
/// Raises error if
/// - source code is syntactically invalid
/// - evaluation encounters a runtime error
///
/// Example:
///
/// ```moonbit nocheck
/// let result = eval_program("(+ 1 2 3)")
/// ```
declare pub fn eval_program(src : String) -> Value raise

///|
/// Evaluates all top-level forms and returns each value in order
///
/// Parameters
///
/// - src: String containing Scheme source code
///
/// Returns an array of Value objects, one for each top-level form
///
/// Raises error if
/// - source code is syntactically invalid
/// - evaluation encounters a runtime error
///
/// Example:
///
/// ```moonbit nocheck
/// let results = eval_program_all("(+ 1 2) (* 3 4)")
/// ```
declare pub fn eval_program_all(src : String) -> Array[Value] raise

///|
/// Renders a runtime value using Scheme surface syntax
///
/// Parameters:
///
/// - value: The Value to convert to string representation
///
/// Returns string representation following Scheme conventions
///
/// Example:
///
/// ```moonbit nocheck
/// let forty_two : Value = { ... }
/// value_to_string(forty_two)  // returns "42"
/// ```
declare pub fn value_to_string(value : Value) -> String
