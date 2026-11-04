///|
/// Credentials and their account epoch stay in memory, outside file URIs.
#derive(Eq)
pub(all) struct Access {
  token : String
  epoch : Int32
}

///|
pub extend Access with Eq::{equal, not_equal}
