///|
/// A host tool result. Tool failures are values; transport failures raise.
pub struct CallResult {
  content : String
  is_error : Bool
  data : Json?
}

///|
/// The host connection failed; a mutation may already have executed.
pub suberror TransportError {
  TransportError(String)
}
