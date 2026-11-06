///|
priv suberror PatternRepairError {
  InvalidRoot
}

///|
impl Show for PatternRepairError with fn output(self, logger) {
  match self {
    InvalidRoot => logger.write_string("path is not absolute")
  }
}
