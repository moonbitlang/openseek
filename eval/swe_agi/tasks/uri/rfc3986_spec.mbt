///|
declare pub type UriParseError

///|
declare pub fn Uri::parse(input : String) -> Uri raise

///|
declare pub type Host

///|
declare type Uri

///|
declare pub fn Uri::fragment(self : Self) -> String?

///|
declare pub fn Uri::host(self : Self) -> String?

///|
declare pub fn Uri::path(self : Self) -> String

///|
declare pub fn Uri::port(self : Self) -> String?

///|
declare pub fn Uri::query(self : Self) -> String?

///|
declare pub fn Uri::scheme(self : Self) -> String

///|
declare pub fn Uri::userinfo(self : Self) -> String?

///|
declare pub fn Uri::resolve(base : Uri, reference : String) -> Uri raise

///|
declare pub fn Uri::to_string(self : Uri) -> String
