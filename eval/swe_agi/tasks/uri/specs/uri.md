# URI (RFC 3986) — parser-oriented specification for this repo

This document is a **practical, test-oriented spec** for the `uri`
package. It summarizes the required subset of **RFC 3986** and the behaviors
asserted by the test suite (notably reference resolution from Section 5).

It is **not** a verbatim copy of RFC 3986.

## Objectives (what the implementation must do)

The `uri` package expects an implementation that can:

1. Parse an absolute URI string into components (scheme, authority parts, path,
   query, fragment).
2. Expose components via getters in `rfc3986_spec.mbt`.
3. Resolve relative references against a base URI using RFC 3986 Section 5.2,
   matching the examples in Section 5.4.
4. Serialize (`Uri::to_string`) such that it matches the expected resolved
   strings in the test suite.

## Primary references

- RFC 3986 (local copy): `uri/specs/rfc3986.txt`
- RFC 3986 (online): https://www.rfc-editor.org/rfc/rfc3986

## Scope and explicit non-goals

### Scope

- RFC 3986 generic syntax:
  - `scheme ":" hier-part [ "?" query ] [ "#" fragment ]`
  - Support for authority-form URIs (`//userinfo@host:port`).
- Component getters required by the MoonBit API:
  - `scheme() : String`
  - `userinfo() : String?`
  - `host() : String?`
  - `port() : String?` (as text, not numeric normalization)
  - `path() : String`
  - `query() : String?`
  - `fragment() : String?`
- Reference resolution: `Uri::resolve(base, reference : String) -> Uri`.

### Non-goals

- Percent-decoding or normalization beyond what is needed for parsing and
  stringification in the tests.
- IDNA / punycode processing.
- Scheme-specific parsing (treat non-hierarchical schemes like `mailto:` as
  having the remainder in `path`).

## API contract (from `uri/rfc3986_spec.mbt`)

- `Uri::parse(input : String) -> Uri raise UriParseError`
- `Uri::resolve(base : Uri, reference : String) -> Uri raise`
- `Uri::to_string(self : Uri) -> String`
- Component getters listed above

The test suite does not assert detailed error messages; it focuses on correct
parsing and resolution.

## Parsing rules (RFC 3986 summary)

### Scheme

- A scheme is the substring before the first `:` that matches RFC 3986’s scheme
  syntax (`ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`).
- Scheme comparison is case-insensitive in RFC 3986, but the API returns the
  parsed textual scheme; tests use lowercase schemes.

### Authority (userinfo, host, port)

If the `hier-part` begins with `//`, then an authority is present:

```
//[userinfo@]host[:port]
```

For this repository:

- `userinfo()` returns the substring before `@` (if any), excluding the `@`.
- `host()` returns the host substring (if any).
- `port()` returns the substring after `:` (if any), excluding the `:`.
- Authority parsing is used in the test suite for `http`, `ftp`, and `telnet`
  examples.

### Path

- Always present as a string (possibly empty).
- For authority-form URIs, the path normally begins with `/` (as in the tests),
  but `mailto:` and `urn:` examples have no authority and the remainder is
  returned as `path` unchanged.

### Query and fragment

- The query is the substring after `?` up to `#` or end.
- The fragment is the substring after `#` to end.
- The returned `query()` / `fragment()` omit the leading delimiter.

## Reference resolution (RFC 3986 Section 5)

`Uri::resolve(base, reference)` must follow RFC 3986 Section 5.2:

1. Parse the reference.
2. If the reference is absolute (has a scheme), it replaces the base entirely.
3. Otherwise inherit the base scheme, and (depending on reference form) inherit
   or replace authority, path, and query.
4. Merge paths where needed, then **remove dot segments** (`.` and `..`) per
   Section 5.2.4.
5. Preserve/replace fragment per the algorithm.

### Dot-segment removal (required by tests)

When normalizing merged paths, `.` and `..` path segments must be removed as
RFC 3986 specifies. The test suite includes both “normal” and “abnormal”
resolution examples from Section 5.4 which depend on correct dot-segment
removal behavior.

## Stringification rules (for test equality)

`Uri::to_string()` should produce:

```
scheme ":" hier-part [ "?" query ] [ "#" fragment ]
```

with exactly the components present after parsing/resolution.

The test suite compares the full serialized string for Section 5.4 examples,
so delimiters must be included/excluded precisely:

- If `query` is present, include `?query`.
- If `fragment` is present, include `#fragment`.
- If authority is present, include `//...` (with userinfo and port delimiters as
  needed).

## Conformance checklist (high value test coverage)

- Parsing of the RFC’s common examples:
  - `http://www.ietf.org/rfc/rfc3986.txt`
  - `ftp://ftp.is.co.za/rfc/rfc1808.txt`
  - `mailto:John.Doe@example.com`
  - `news:comp.infosystems.www.servers.unix`
  - `tel:+1-816-555-1212`
  - `telnet://192.0.2.16:80/`
  - `urn:oasis:names:...`
- Query + fragment extraction
- Full reference resolution behavior matching RFC 3986 §5.4.1 and §5.4.2

## ABNF (implementation reference)

RFC 3986 defines an ABNF grammar; for this repo, a simplified but useful subset
is:

```text
URI         = scheme ":" hier-part [ "?" query ] [ "#" fragment ]
hier-part   = "//" authority path-abempty / path-absolute / path-rootless / path-empty
authority   = [ userinfo "@" ] host [ ":" port ]
userinfo    = *( unreserved / pct-encoded / sub-delims / ":" )
host        = IP-literal / IPv4address / reg-name
port        = *DIGIT
query       = *( pchar / "/" / "?" )
fragment    = *( pchar / "/" / "?" )
```

This suite does not require full percent-encoding validation, but the parsing
must correctly split components on the delimiter characters at the right layer.

## Reference resolution: algorithm outline (RFC 3986 §5.2)

The suite includes the RFC’s section 5.4 examples, which essentially validate:

1. **Parse reference** into (scheme, authority, path, query, fragment).
2. If reference has a scheme:
   - target.scheme = reference.scheme
   - target.authority/path/query = reference.authority/path/query
   - remove dot segments from reference.path
3. Else:
   - target.scheme = base.scheme
   - If reference has authority:
     - target.authority = reference.authority
     - target.path = remove_dot_segments(reference.path)
     - target.query = reference.query
   - Else:
     - target.authority = base.authority
     - If reference.path is empty:
       - target.path = base.path
       - target.query = reference.query if present else base.query
     - Else if reference.path starts with "/":
       - target.path = remove_dot_segments(reference.path)
       - target.query = reference.query
     - Else:
       - target.path = remove_dot_segments( merge(base.path, reference.path) )
       - target.query = reference.query
4. target.fragment = reference.fragment (even if empty) if present

Implementations should follow the RFC directly; ad-hoc “path join” logic tends
to fail the abnormal examples.

## Dot-segment removal: additional notes

The RFC’s dot-segment removal algorithm has unintuitive cases that appear in
the abnormal examples:

- `g/..` resolves to a path ending with `/` (directory).
- Leading `..` segments beyond the root are removed when the base has authority
  and the merged path is absolute.
- Segments like `..g` and `.g` are **not** dot segments and must remain.

## Component extraction corner cases

The test suite already covers the most important extraction cases; additional
rules to make explicit:

- `//g` as a reference means “inherit scheme, replace authority with g”.
- `?y` replaces query but keeps base path.
- `#s` replaces fragment but keeps base path and query.
- A scheme like `mailto:` has no authority; everything after `mailto:` is the
  path for this repo’s API.

