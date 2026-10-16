///|
pub suberror InstallError {
  InstallError(String, String)
}

///|
pub impl Show for InstallError with fn output(self, logger) {
  let InstallError(stage, message) = self
  logger.write_string(stage + ": " + message)
}

///|
pub(all) struct Installation {
  build_id : String
  platform : String
  manifest_sha256 : String
  launcher : String
  home : String
  reused : Bool
}

///|
pub extend InstallError with Show::{to_string, output}
