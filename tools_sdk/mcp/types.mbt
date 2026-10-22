///|
/// An MCP tool's result. A tool failure is a value with `is_error`; a
/// transport failure raises `TransportError`.
pub struct CallResult {
  /// The tool's text, which names each saved image's file.
  content : String
  is_error : Bool
  /// The tool's structured result, when it has one and it fits beside the
  /// text.
  data : Json?
  /// Files the host saved the tool's images in. Show one to the model by
  /// passing its path to `@openseek_tools.call("read_image", { "path": path })`.
  images : Array[String]
}

///|
/// One page of an MCP tool search. The same tools appear twice: `text` renders
/// them for the model once a script prints it, and `tools` holds them as
/// records with their raw JSON Schemas for the script to select from.
pub struct SearchPage {
  /// The page rendered for the model.
  text : String
  /// The named server's instructions, on the first page of a search that
  /// names a `server`.
  instructions : String?
  tools : Array[Tool]
  /// The number of matching tools across every page.
  total : Int32
  /// The `offset` that continues the listing, when more tools match.
  next_offset : Int32?
}

///|
/// An MCP tool as its server describes it. `server` and `name` are what
/// `call` takes.
pub struct Tool {
  server : String
  name : String
  description : String
  /// The JSON Schema of the tool's arguments.
  input_schema : Json
  /// The JSON Schema of the result `data`, when the server declares one.
  output_schema : Json?
}

///|
/// The search was refused (an unknown server or invalid arguments), or the
/// host's catalog could not be downloaded. A search changes nothing, so it is
/// always safe to run again.
pub suberror SearchError {
  SearchError(String)
}

///|
/// The reason, so a script that lets the error escape prints why.
pub impl Show for SearchError with fn output(self, logger) {
  let SearchError(message) = self
  logger.write_string("SearchError: \{message}")
}

///|
pub extend SearchError with Show::{to_string, output}

///|
/// The MCP host connection failed, or this run has no MCP host; a call may
/// already have executed.
pub suberror TransportError {
  TransportError(String)
}

///|
/// The reason, so a script that lets the error escape prints why.
pub impl Show for TransportError with fn output(self, logger) {
  let TransportError(message) = self
  logger.write_string("TransportError: \{message}")
}

///|
pub extend TransportError with Show::{to_string, output}
