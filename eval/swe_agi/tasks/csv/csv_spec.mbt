///|
declare pub(all) type Csv

///|
declare pub type ParseError

///|
declare pub fn ParseError::to_string(self : ParseError) -> String

///|
/// Parse CSV text into a structured Csv value
///
/// Parameters:
///
/// - `input`: CSV text as StringView
///
/// Returns:
///
/// - `Ok(Csv)`: Successfully parsed CSV data
/// - `Err(ParseError)`: Parse error with details
declare pub fn parse(input : StringView) -> Result[Csv, ParseError]

///|
/// JSON encoding for CSV test validation
/// ---------------------------------------
/// The CSV data is encoded to JSON for test verification following this schema:
///
/// - CSV records correspond to JSON arrays of arrays
/// - Each record is a JSON array of field values (strings)
/// - Empty fields are represented as empty strings ("")
/// - The result is a JSON object with a "records" field
///
/// Examples:
///
///     CSV                     JSON
///
///     a,b,c                   {"records": [
///     1,2,3                     ["a", "b", "c"],
///                               ["1", "2", "3"]
///                             ]}
///
/// <!-- -->
///
///     name,age                {"records": [
///     Alice,30                  ["name", "age"],
///     Bob,25                    ["Alice", "30"],
///                               ["Bob", "25"]
///                             ]}
///
/// <!-- -->
///
///     a,"b,c",d               {"records": [
///     1,"2,3",4                 ["a", "b,c", "d"],
///                               ["1", "2,3", "4"]
///                             ]}
///
/// <!-- -->
///
///     empty,,fields           {"records": [
///     ,middle,                  ["empty", "", "fields"],
///                               ["", "middle", ""]
///                             ]}
///
/// Note that:
/// - All field values are JSON strings
/// - Quoted fields have quotes removed in the JSON representation
/// - Escaped quotes within fields are unescaped
/// - Line breaks within quoted fields are preserved
///
declare pub fn Csv::to_test_json(self : Csv) -> Json
