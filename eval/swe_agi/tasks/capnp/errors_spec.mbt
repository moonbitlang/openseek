///|
pub suberror CapnpError {
  Message(String)
  PointerOutOfBounds(Int, Int)
  InvalidPointerKind(UInt)
  InvalidData(String)
  InvalidPointer(String)
  InvalidList(String)
  InvalidText(String)
  TraversalLimitExceeded(Int)
}

///|
declare pub fn CapnpError::to_string(self : CapnpError) -> String
