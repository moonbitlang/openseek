///|
/// Opaque URL type representing a parsed WHATWG URL.
declare pub(all) type Url

///|
/// Validation error type for URL parsing failures.
declare pub type ValidationError

///|
/// Parse a URL string, optionally with a base URL for relative resolution.
/// Returns None if parsing fails.
declare pub fn Url::parse(
  input : String,
  base? : Url,
  validation_errors? : Array[ValidationError] = [],
) -> Url?

///|
/// Serialize URL to string per WHATWG URL spec.
declare pub fn Url::to_string(self : Url) -> String

///|
/// Get the href (alias for to_string).
declare pub fn Url::href(self : Url) -> String

///|
/// Get the protocol (scheme + ":").
declare pub fn Url::protocol(self : Url) -> String

///|
/// Get the username.
declare pub fn Url::username(self : Url) -> String

///|
/// Get the password.
declare pub fn Url::password(self : Url) -> String

///|
/// Get the host (hostname:port if port is present).
declare pub fn Url::host(self : Url) -> String

///|
/// Get the hostname (without port).
declare pub fn Url::hostname(self : Url) -> String

///|
/// Get the port as a string.
declare pub fn Url::port(self : Url) -> String

///|
/// Get the pathname (serialized path).
declare pub fn Url::pathname(self : Url) -> String

///|
/// Get the search (query string with leading "?" if present).
declare pub fn Url::search(self : Url) -> String

///|
/// Get the hash (fragment with leading "#" if present).
declare pub fn Url::hash(self : Url) -> String

///|
/// Set the full href (re-parse and replace all components).
declare pub fn Url::set_href(self : Url, href : String) -> Unit

///|
/// Set the protocol (scheme + ":").
declare pub fn Url::set_protocol(self : Url, protocol : String) -> Unit

///|
/// Set the username.
declare pub fn Url::set_username(self : Url, username : String) -> Unit

///|
/// Set the password.
declare pub fn Url::set_password(self : Url, password : String) -> Unit

///|
/// Set the host (hostname:port if port is present).
declare pub fn Url::set_host(self : Url, host : String) -> Unit

///|
/// Set the hostname (without port).
declare pub fn Url::set_hostname(self : Url, hostname : String) -> Unit

///|
/// Set the port as a string.
declare pub fn Url::set_port(self : Url, port : String) -> Unit

///|
/// Set the pathname (serialized path).
declare pub fn Url::set_pathname(self : Url, pathname : String) -> Unit

///|
/// Set the search (query string with leading "?" if present).
declare pub fn Url::set_search(self : Url, search : String) -> Unit

///|
/// Set the hash (fragment with leading "#" if present).
declare pub fn Url::set_hash(self : Url, hash : String) -> Unit

///|
/// Get the origin.
declare pub fn Url::origin(self : Url) -> String
