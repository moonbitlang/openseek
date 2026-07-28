///|
declare pub(all) type Toml

///|
declare pub type ParseError

///|
declare pub fn ParseError::to_string(self : ParseError) -> String

///|
declare pub fn parse(input : StringView) -> Result[Toml, ParseError]

///|
/// JSON encoding
/// -------------
/// The following JSON encoding applies equally to both encoders and decoders:
///
/// - TOML tables correspond to JSON objects.
/// - TOML arrays correspond to JSON arrays.
/// - TOML values correspond to a JSON object of the form:
///   `{"type": "{TOML_TYPE}", "value": "{TOML_VALUE}"}`
///
/// In the above, `TOML_TYPE` may be one of:
///
/// - string
/// - integer
/// - float
/// - bool
/// - datetime
/// - datetime-local
/// - date-local
/// - time-local
///
/// `TOML_VALUE` is always a JSON string.
///
/// Empty tables correspond to empty JSON objects (`{}`) and empty arrays correspond
/// to empty JSON arrays (`[]`).
///
/// Offset datetimes should be encoded in RFC 3339; Local datetimes should be
/// encoded following RFC 3339 without the offset part. Local dates should be
/// encoded as the date part of RFC 3339 and local times as the time part.
///
/// Examples:
///
///     TOML                JSON
///
///     a = 42              {"type": "integer", "value": "42"}
///
/// <!-- -->
///
///     [tbl]               {"tbl": {
///     a = 42                  "a": {"type": "integer", "value": "42"}
///                         }}
///
/// <!-- -->
///
///     a = ["a", 2]        {"a": [
///                             {"type": "string",  "value": "a"},
///                             {"type": "integer", "value": "2"}
///                         ]}
///
/// <!-- -->
///
///     [[arr]]             {"arr": [
///     a = 1                   {
///     b = 2                       "a": {"type": "integer", "value": "1"},
///     [[arr]]                     "b": {"type": "integer", "value": "2"}
///     a = 3                   }, {
///     b = 4                       "a": {"type": "integer", "value": "3"},
///                                 "b": {"type": "integer", "value": "4"}
///                             }
///                         ]}
///
/// Note that the only JSON values ever used are objects, arrays and strings.
///
/// An example implementation can be found in the BurnSushi/toml:
///
/// - [Add tags](https://github.com/BurntSushi/toml/blob/master/internal/tag/add.go)
/// - [Remove tags](https://github.com/BurntSushi/toml/blob/master/internal/tag/rm.go)
declare pub fn Toml::to_test_json(self : Toml) -> Json
