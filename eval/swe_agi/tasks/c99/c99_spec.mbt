///|
/// C99 parser public API required by the spec-tests in this directory.
///
/// This file is **declaration-only**: it provides signatures (not
/// implementations) so you can implement the real logic in other `.mbt` files
/// under the same directory without naming conflicts.
///
/// The test suite expects:
/// - `parse(...)` to produce a `CProgram` AST for a translation unit, and
/// - `CProgram::to_test_json()` to encode the AST into a stable, explicit JSON schema.
///
declare pub(all) type CProgram

///|
/// Parse errors raised by `parse`.
pub(all) suberror ParseError {
  ParseError(String)
}

///|
/// Parse a C99 translation unit from source text.
declare pub fn parse(code : StringView) -> CProgram raise ParseError

///|
/// Encode the parsed program into the explicit test JSON schema used by this
/// test suite.
declare pub fn CProgram::to_test_json(self : CProgram) -> Json
