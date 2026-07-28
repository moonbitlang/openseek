///|
/// Parse and evaluate a jq query against a JSON string input, collecting results.
///
/// Parameters:
/// - `query`: A jq query string (e.g., ".foo", ".[0]", "map(. + 1)")
/// - `input`: JSON string to parse and query
///
/// Returns:
/// - All result values as `Array[Json]`
///
/// Raises on parse or evaluation errors
declare pub fn run(query : String, input : String) -> Array[Json] raise
