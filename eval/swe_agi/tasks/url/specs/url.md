# WHATWG URL — parser-oriented specification for this repo

This document is a **practical, test-oriented spec** for the `url`
package. It summarizes the WHATWG URL Standard behaviors required by this
repository’s API and test suite (including WPT vectors included in this repo).

It is **not** a verbatim copy of the WHATWG URL Standard.

## Objectives (what the implementation must do)

The `url` package expects an implementation that can:

1. Parse a URL string according to the WHATWG URL parsing algorithm, optionally
   using a base URL for relative resolution.
2. Expose URL components via getters (`href`, `protocol`, `hostname`, etc.).
3. Support setters that update the URL in a standards-compatible way (WPT
   “setters” tests).
4. Serialize URLs canonically via `Url::to_string()` / `Url::href()`.
5. Collect validation errors when `validation_errors` is provided.

## Primary references

- WHATWG URL Standard: https://url.spec.whatwg.org/
- This repository vendors the spec source and WPT fixtures under:
  - `url/specs/whatwg/` (spec source)
  - `url/specs/wpt/` (Web Platform Tests vectors)

## Scope and explicit non-goals

### Scope

- The suite targets the WHATWG “URL” concept (not RFC 3986 generic URIs).
- Support for:
  - “Special” schemes (http, https, ws, wss, ftp, file) and their rules.
  - Non-special (opaque) URLs where applicable.
  - Username/password, host, port, path, query, fragment.
  - Host parsing for domain, IPv4, IPv6, and opaque hosts.
  - Relative URL parsing against a base URL.

### Non-goals

- Networking, DNS, or any fetch behavior.
- Full IDNA correctness beyond what WPT vectors require.
- Full “URLSearchParams” API (not part of this package).

## API contract (from `url/url_spec.mbt`)

### Construction and serialization

- `Url::parse(input : String, base? : Url, validation_errors? : Array[ValidationError] = []) -> Url?`
  - Returns `None` on parse failure.
  - When `validation_errors` is provided, append non-fatal validation issues.
- `Url::to_string(self : Url) -> String`
- `Url::href(self : Url) -> String` (alias for `to_string`)
- `Url::origin(self : Url) -> String`

### Getters (all return strings in serialized form)

- `protocol()` includes the trailing `:` (e.g. `"https:"`).
- `host()` is `hostname:port` when the port is present and non-default, else
  just `hostname` (per standard).
- `hostname()` omits the port.
- `port()` returns the port as a string or empty string if absent (per standard
  getter semantics).
- `pathname()` is the serialized path.
- `search()` includes leading `?` when query exists, else empty string.
- `hash()` includes leading `#` when fragment exists, else empty string.
- `username()`, `password()` return the stored credentials (possibly empty).

### Setters

The following must update the URL in a WHATWG-compatible way (as validated by
WPT fixtures in this repo):

- `set_href`, `set_protocol`, `set_username`, `set_password`, `set_host`,
  `set_hostname`, `set_port`, `set_pathname`, `set_search`, `set_hash`.

## Model overview (WHATWG terminology)

URLs consist of:

- `scheme` (protocol)
- `username` / `password`
- `host` (domain / IPv4 / IPv6 / opaque-host) or null
- `port` or null
- `path` (list of segments, or opaque path depending on scheme)
- `query` or null
- `fragment` or null

The standard defines a **state machine** parser over Unicode scalar values
which produces this structured result plus a canonical serialization.

## Parsing and serialization rules (test-oriented summary)

The WPT-based tests strongly constrain behavior. Implementations should follow
the WHATWG algorithm rather than “ad hoc” parsing. Key required behaviors:

### General preprocessing

- Strip leading/trailing C0 control and whitespace as the spec requires.
- Replace certain code points (e.g. tabs/newlines) where the algorithm calls for
  it, reporting validation errors when applicable.

### Special vs non-special schemes

- Special schemes use host parsing and path segment normalization rules.
- Non-special (opaque) URLs have different path handling and do not treat `\`
  as a path separator, etc.

### Authority and credentials

- Parse `//` authority when present.
- Support `username:password@host:port` parsing, including percent-encoding
  rules for credentials.

### Host parsing

- IPv6 is bracketed (`[::1]`) and serialized with brackets.
- IPv4 parsing supports non-decimal forms in the standard (WPT may cover),
  canonicalizing to dotted-decimal.
- Domain hosts are processed through IDNA as the standard requires (WPT vectors
  define expected outcomes).
- Opaque hosts may appear for non-special schemes.

### Path processing

- For special URLs, path is a list of segments; dot segments (`.` / `..`) are
  normalized per the algorithm during parsing and resolution.
- For `file:` URLs, Windows drive letter behaviors and host rules are tested by
  WPT.

### Query and fragment

- Query is introduced by `?` and fragment by `#`.
- Serialization must include or omit delimiters exactly as getters specify.

### Relative resolution

When `base` is provided, parse relative references using the WHATWG algorithm
(not RFC 3986). WPT vectors validate many edge cases around:

- Missing scheme vs same-scheme resolution
- Authority replacement
- Path merging and dot-segment processing
- `file:` base URL peculiarities

## Validation errors

When `validation_errors` is supplied to `Url::parse`, the implementation should
collect “non-fatal” issues described by the standard (e.g. invalid code points,
unexpected backslashes in special URLs, etc.). The exact error taxonomy is
defined by `ValidationError` in `url/url_spec.mbt` and the WPT fixtures.

## Conformance checklist (high value test coverage)

- Basic parsing + canonical serialization (`href`)
- Getters: `protocol`, `username`, `password`, `host`, `hostname`, `port`,
  `pathname`, `search`, `hash`, `origin`
- Setters: all `set_*` methods validated by WPT setter vectors
- Host parsing: domain, IPv4, IPv6, opaque host
- Special schemes + `file:` corner cases
- Relative resolution against a base URL (WPT)

## Getter/setter semantics (WHATWG-style, test-oriented)

The WHATWG URL Standard defines not only parsing but also how “setters” mutate
the internal URL record. The WPT fixtures in this repo validate many details;
these rules are worth making explicit for implementers.

### `href` / `to_string`

- Serialization is canonical for the URL record.
- Special-scheme URLs normalize:
  - scheme casing to lowercase
  - host casing/punycode per IDNA steps
  - default ports omitted
  - dot-segment processing and path normalization

### `protocol` and `set_protocol`

- Getter returns `scheme + ":"`.
- Setting protocol must accept with or without trailing `:`.
- Changing scheme may change the URL’s parsing mode (special vs non-special),
  affecting host/path semantics.

### Host/port and setters

- `host()` is `hostname:port` only when a port is present and non-default.
- `hostname()` never includes the port.
- `port()` is a string or empty string when absent.

Setters:

- `set_host(host)` parses `hostname[:port]` together.
- `set_hostname(hostname)` parses only the hostname (no `:port` suffix).
- `set_port(port)` parses digits; setting a default port may clear the stored
  port (depending on scheme rules).

### Credentials and setters

- `username`/`password` are serialized with percent-encoding per the standard.
- Setting them applies the standard’s encoding rules and may produce validation
  errors for disallowed code points.

### `pathname`, `search`, `hash` and setters

- `search()` includes leading `?` when query exists, else empty string.
- `hash()` includes leading `#` when fragment exists, else empty string.

Setting:

- `set_pathname` reparses/normalizes the new path according to scheme rules.
- `set_search` accepts with or without leading `?`; empty clears query.
- `set_hash` accepts with or without leading `#`; empty clears fragment.

## “Special” schemes and default ports

Special schemes in the standard: `ftp`, `file`, `http`, `https`, `ws`, `wss`.

Default ports (used for normalization/omission):

- `http`: 80
- `https`: 443
- `ws`: 80
- `wss`: 443
- `ftp`: 21

## `file:` notes (frequently tested by WPT)

`file:` parsing includes platform-ish rules. WPT vectors in this repo commonly
cover:

- Drive-letter handling (`C:` and variations) and normalization.
- Host rules: null/empty host vs special “localhost” cases.
- Backslash handling and path normalization.

Treat WPT fixtures as canonical for `file:` details.

## Validation errors collection

When `validation_errors` is passed to `Url::parse`, the implementation should:

- Append (not replace) validation errors encountered.
- Record non-fatal issues described by the standard and/or asserted by WPT,
  using the repo’s `ValidationError` taxonomy.
