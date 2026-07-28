///|
declare pub(all) type Ini

///|
declare pub type ParseError

///|
declare pub fn ParseError::to_string(self : ParseError) -> String

///|
/// Parse INI text into a structured Ini value
///
/// Parameters:
///
/// - `input`: INI text as StringView
///
/// Returns:
///
/// - `Ok(Ini)`: Successfully parsed INI data
/// - `Err(ParseError)`: Parse error with details
declare pub fn parse(input : StringView) -> Result[Ini, ParseError]

///|
/// JSON encoding for INI test validation
/// ---------------------------------------
/// The INI data is encoded to JSON for test verification following this schema:
///
/// - INI sections correspond to JSON objects
/// - Each section contains key-value pairs as JSON strings
/// - Global key-value pairs (before any section) go in a special "" section
/// - All values are represented as JSON strings
///
/// Examples:
///
///     INI                     JSON
///
///     key=value               {"": {"key": "value"}}
///
/// <!-- -->
///
///     [section]               {"section": {"key": "value"}}
///     key=value
///
/// <!-- -->
///
///     global=yes              {"": {"global": "yes"},
///     [section]                "section": {"key": "value"}}
///     key=value
///
/// <!-- -->
///
///     [section1]              {"section1": {"a": "1"},
///     a=1                      "section2": {"b": "2"}}
///     [section2]
///     b=2
///
/// Note that:
/// - All values are JSON strings (no type conversion)
/// - Comments are stripped during parsing
/// - Whitespace around keys and values is preserved or trimmed based on INI spec
/// - Empty sections are represented as empty JSON objects
///
declare pub fn Ini::to_test_json(self : Ini) -> Json
