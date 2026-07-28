# XML 1.0 + Namespaces — streaming parser specification for this repo

This document is a **practical, test-oriented spec** for the `xml`
package. It summarizes the behaviors required by this repository’s streaming
pull-parser API (Reader/Writer) and the conformance tests in this repo.

It is **not** a verbatim copy of the W3C XML specifications.

## Objectives (what the implementation must do)

The `xml` package expects an implementation that can:

1. Parse XML from strings/files using a pull-parser model (`Reader`).
2. Emit a stream of `Event`s representing the document structure.
3. Provide a reference formatting (`to_libxml_format`) used by tests for event
   comparison.
4. Generate XML output (`Writer`) and provide text escaping/unescaping helpers.
5. Reject not-well-formed XML with an appropriate `XmlError`.

## Primary references

- XML 1.0 (Fifth Edition): https://www.w3.org/TR/xml/
- Namespaces in XML 1.0 (Third Edition): https://www.w3.org/TR/xml-names/
- quick-xml inspiration (as noted in `xml_spec.mbt`): https://github.com/tafia/quick-xml

The test corpus in this repo is organized as W3C-style “valid” and “not-wf”
cases.

## Scope and explicit non-goals

### Scope

- **Non-validating** XML parsing:
  - Ensure well-formedness.
  - Parse and surface certain markup constructs (doctype declaration, PI,
    comments, CDATA).
  - Record general entities declared in an internal subset and expand them in
    document content, including replacement text that contains markup.
  - Do not validate against DTDs.
- UTF-8 input only (per README).
- XML 1.0 only (per README).

### Non-goals

- DTD validation, external entities, parameter entities, schema validation.
- Non-UTF-8 encodings.
- XML 1.1 specifics.

## API contract (from `xml/xml_spec.mbt`)

### Reader

- `Reader::from_string(input : String) -> Reader`
- `Reader::from_file(path : String) -> Reader raise @fs.IOError`
- `Reader::read_event(self : Reader) -> Event raise XmlError`
- `Reader::is_eof(self : Reader) -> Bool`
- `Reader::line(self) -> Int`, `Reader::column(self) -> Int` (1-indexed)
- `Reader::read_events_until_eof(self) -> Array[Event] raise XmlError`
  - Must include the final `Eof` event.

### Writer

- `Writer::new() -> Writer`
- `Writer::write_event(self, event : Event) -> Unit`
- Convenience methods:
  - `start_element`, `end_element`, `empty_element`, `text`, `cdata`, `comment`
- `Writer::to_string(self) -> String`

### Helpers

- `escape(text : String) -> String`
- `unescape(text : String) -> String raise XmlError`
- `to_libxml_format(events : Array[Event]) -> String`
- `Event::to_string(self) -> String`

### Errors

`XmlError` includes:

- `UnexpectedEof`
- `InvalidSyntax(String)`
- `UnmatchedTag(expected~ : String, found~ : String)`
- `InvalidAttribute(String)`
- `InvalidEntity(String)`

## Event model (test-oriented)

The tests compare the event stream using `to_libxml_format(events)`, which
renders events in a stable, libxml-like textual format. Expected event kinds
include:

- `DocType("name")`
- `Start({name: "...", attributes: [...]})`
- `End("name")`
- `Empty({name: "...", attributes: [...]})`
- `Text("...")`
- `Comment("...")`
- `PI(target="...", data="...")`
- `Eof`

The exact event shapes are defined by `Event::to_string` and `to_libxml_format`
implementations (they are part of the contract for tests).

## XML well-formedness rules required by tests

The W3C-derived tests exercise well-formedness rules such as:

### Tags and nesting

- Start-tags and end-tags must be properly nested.
- End tags must match the most recent open element; mismatches should raise
  `UnmatchedTag`.
- Empty-element tags (`<x/>`) produce `Empty(...)` events.

### Attributes

- Attributes appear in start-tags/empty tags and are rendered as an ordered list
  of `(name, value)` pairs in the expected event output.
- Attribute values may be single-quoted or double-quoted.
- Whitespace around `=` is allowed (tests include `a1 = "v1"` variants).
- Invalid attribute syntax should raise `InvalidAttribute` or `InvalidSyntax`.

### Names

- XML Name/NCName rules apply. The test suite includes many cases for legal name
  characters and name-start characters.
- The suite includes names with colons (and README mentions namespaces), so the
  parser must accept colon where XML allows it.

### Character and entity references

The suite expects:

- Predefined entities: `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`
- Numeric character references: `&#32;`, `&#x20;`, etc.

Entity references in character data must be expanded into `Text(...)` content
as shown in valid tests (e.g. `&amp;&lt;...` becomes `Text("&<>\"'")`).

Invalid entities should raise `InvalidEntity`.

### CDATA sections

- `<![CDATA[...]]>` yields character data in the event stream as `Text("...")`
  (tests treat CDATA content as text without markup interpretation).

### Comments and processing instructions

- Comments: `<!-- ... -->` produce `Comment("...")`.
- Processing instructions: `<?target data?>` produce `PI(target="...", data="...")`.

### Doctype declarations

The suite includes internal subset examples like:

```
<!DOCTYPE doc [
  <!ELEMENT doc (#PCDATA)>
]>
```

The parser is non-validating, but must recognize the doctype and emit a
`DocType("doc")` event in the expected position.

## Error conditions (must reject)

The invalid suite contains “not-wf” cases. At minimum, the parser must reject:

- Unterminated markup / premature EOF → `UnexpectedEof`
- Malformed tags/attributes/PI/comment/CDATA syntax → `InvalidSyntax` / `InvalidAttribute`
- Mismatched/unbalanced tags → `UnmatchedTag`
- Invalid entity reference syntax → `InvalidEntity`

## Conformance checklist (high value test coverage)

- Streaming event correctness for W3C “valid” corpus:
  - doctype + element events + text/entity expansion
  - attributes (quoting, whitespace, ordering)
  - PI, comments, CDATA
- Rejection of W3C “not-wf” corpus with correct error category
- `to_libxml_format` output stability for snapshots
- Writer output for basic element/text/cdata/comment generation

## Whitespace and text event rules

The W3C-derived corpus includes many cases involving whitespace:

- Whitespace inside tags (e.g. `<doc ></doc>`) must be accepted.
- Attribute whitespace around `=` must be accepted.
- Character data whitespace inside elements should be preserved as `Text(...)`
  events where present.

Unless a test demonstrates otherwise, the safest policy is:

- Preserve character data exactly as parsed after entity expansion.
- Do not coalesce or trim text unless the event format requires it.

## Name syntax and namespaces (practical subset)

The README claims “XML 1.0 + Namespaces 1.0” and “full Unicode name character
support”. The test corpus includes:

- Names with colons (e.g. an attribute named `:`).
- A wide range of ASCII name-start/name chars.

For this suite:

- Accept XML 1.0 Name production for element/attribute/PI target names.
- Accept colons where XML allows them; treat them as part of the name string in
  events (the tests compare literal `name: \"...\"` strings).

Namespace *resolution* (binding prefixes to URIs) is not exposed by the public
API, so it is sufficient to parse names and preserve them; do not attempt to
rewrite prefixes.

## DTD/doctype handling (non-validating)

The valid tests include doctype declarations with an internal subset. The parser
must:

- Recognize `<!DOCTYPE ...>` and extract the root name for `DocType("name")`.
- Read general entity declarations from the internal subset without attempting
  DTD validation.
- Continue parsing element content after the doctype.

When a declared general entity is referenced in document content, expand its
replacement text. Replacement text is parsed as XML content rather than always
being emitted as a literal text node.

## Entity expansion rules

The test corpus asserts that entity references in character data become decoded
characters in `Text(...)`, including:

- `&amp;` → `&`
- `&lt;` → `<`
- `&gt;` → `>`
- `&quot;` → `\"`
- `&apos;` → `'`
- numeric `&#...;` and `&#x...;` references

It also covers general entities declared in an internal DTD subset. Their
replacement text may be empty, plain character data, or markup that produces
element events.

Error handling:

- Unknown entities should raise `InvalidEntity`.
- Malformed numeric references should raise `InvalidEntity` or `InvalidSyntax`.

## Line/column reporting

`Reader::line()` and `Reader::column()` are part of the contract.

Practical expectations:

- Both are 1-indexed.
- Newline handling should treat CRLF as a single newline for counting purposes.
- On errors, line/column should point near the offending construct (tests may
  not assert exact coordinates, but they are important for usability).

## Writer escaping rules

The writer must escape text and attribute values in the usual XML way:

- `&` → `&amp;`
- `<` → `&lt;`
- `>` → `&gt;` (often optional in text, but safe)
- `\"` in attributes → `&quot;`
- `'` in attributes when using single quotes → `&apos;` (depending on quoting style)

CDATA:

- `Writer::cdata` emits `<![CDATA[...]]>` and must reject or split content that
  contains the forbidden `]]>` sequence if the tests require strictness.
