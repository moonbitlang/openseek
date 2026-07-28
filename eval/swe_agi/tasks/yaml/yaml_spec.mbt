///|
/// Formal error types for YAML parsing.
declare pub type ParseError

///|
declare pub fn ParseError::to_string(self : ParseError) -> String

///|
/// Opaque YAML document type.
declare pub(all) type Yaml

///|
/// Parse YAML content from a string.
/// Returns a Yaml document or raises ParseError on invalid input.
declare pub fn parse(input : String) -> Result[Yaml, ParseError]

///|
/// Convert a Yaml document to a JSON.
declare pub fn Yaml::to_json(yaml : Yaml) -> Json

///|
/// Serialize a Yaml document back to a YAML string.
declare pub fn Yaml::to_string(yaml : Yaml) -> String
