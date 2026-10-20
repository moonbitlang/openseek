///|
/// Credentials and their account epoch stay in memory, outside file URIs.
pub(all) struct Access {
  token : String
  epoch : Int32
} derive(Eq)

///|
pub extend Access with Eq::{equal, not_equal}
