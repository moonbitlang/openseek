# HTML Living Standard (WHATWG) — HTML5 parser specification for this repo

This document is a **practical, test-oriented spec** for the `html5`
package. It summarizes the behavior required by this repository’s MoonBit API
and conformance tests (tokenizer + tree construction).

It is **not** a verbatim copy of the HTML Living Standard.

## Objectives (what the implementation must do)

The `html5` package expects an implementation that can:

1. Tokenize HTML input according to the WHATWG tokenizer, including character
   references and error handling.
2. Build a DOM-like document tree according to the WHATWG tree construction
   algorithm (insertion modes, adoption agency algorithm, foster parenting,
   template handling, etc.).
3. Serialize a document back to HTML (`Document::to_html`) and provide a stable
   debug tree dump (`Document::dump`) used by tests.
4. Be **error-tolerant** like browsers: many malformed inputs must still produce
   a valid document with recorded parse errors.

## Primary references

- HTML Living Standard: https://html.spec.whatwg.org/
- html5lib test corpus (the provided suite is derived from it)
  - https://github.com/html5lib/html5lib-tests

## Scope and explicit non-goals

### Scope

- Parsing complete HTML documents and fragments via:
  - `parse(input) -> Document`
  - `parse_with_errors(input) -> (Document, Array[ParseError])`
  - `parse_with_scripting(input) -> Document`
- Tokenization without tree building via:
  - `tokenize(input) -> (Array[Token], Array[ParseError])`
- DOM access and mutation via `Document::*` methods declared in `html5_spec.mbt`
  (node IDs, attributes, text content, etc.).

### Non-goals

- CSS parsing, JS execution, layout, rendering.
- Full browser networking or resource loading.
- Full HTML serialization edge-case equivalence beyond what the test suite
  asserts.

## API contract (from `html5/html5_spec.mbt`)

Core entry points:

- `parse(input : String) -> Document`
- `parse_with_errors(input : String) -> (Document, Array[ParseError])`
- `parse_with_scripting(input : String) -> Document`
- `tokenize(input : String) -> (Array[Token], Array[ParseError])`

Document utilities used by tests:

- `Document::dump(self) -> String` (stable tree view)
- `Document::to_html(self) -> String`

Token utilities used by tests:

- `Token::to_string(self) -> String` (stable token rendering)
- `Show` impl for `Token` delegates to `to_string`

The test suite generally checks:

- `tokenize(...)` tokens via `inspect(tokens, content="[...]")`
- `parse(...)` trees via `inspect(doc.dump(), content=(...))`
- Some serialization via `doc.to_html()`

## Test-oriented behavioral requirements

### Document structure defaults

The tree construction algorithm must produce implied elements as browsers do.
In particular, even for fragment-like inputs, the tree dump expected by tests
typically includes:

- `<html>`
  - `<head>`
  - `<body>`

### `Document::dump` format (test oracle)

`Document::dump()` is treated as the “oracle” for tree-construction tests.
The expected dump format used throughout the suite is:

- Indented element lines like:
  - `<html>`
  - `  <head>`
  - `  <body>`
  - `    <p>`
- Text node lines rendered as quoted strings:
  - `      "text"`

Exact indentation and quoting must match the test expectations.

### Tokenization and character references

The tokenizer must:

- Implement the WHATWG tokenizer state machine (the README claims “80 states”).
- Implement character references:
  - Numeric `&#...;` and `&#x...;`
  - Named character references (README claims “2,231 named character references”)
- Produce stable token strings via `Token::to_string` that match the suite’s
  snapshots (e.g. `Character('|')`, `EOF`, etc.).

Malformed inputs must typically:

- Emit appropriate parse errors, and
- Continue tokenizing/parsing to produce tokens/tree per the spec’s error
  recovery rules.

### Tree construction (insertion modes and recovery)

The tree builder must follow the WHATWG algorithm, including (as heavily tested):

- Mis-nested formatting elements resolution (adoption agency algorithm).
- Implied end tags and scope checking.
- Table foster parenting behavior.
- Handling of foreign content (`svg`, `math`) where exercised by tests.
- `noscript` behavior difference when scripting is enabled:
  - `parse_with_scripting` treats `<noscript>` content as raw text in the
    relevant contexts per the standard.

### Error collection

- `parse_with_errors` and `tokenize` return a list of `ParseError`s encountered.
- Tests generally do not require exact error text, but do require errors to be
  recorded in “obviously malformed” cases and parsing to continue.

## Conformance checklist (high value test coverage)

- Tokenizer:
  - numeric + named character references
  - state-machine corner cases and EOF handling
  - stable token string rendering
- Tree construction:
  - implied `<html>/<head>/<body>`
  - adoption agency algorithm cases
  - table foster parenting
  - foreign content transitions
  - `noscript` with/without scripting
- Document serialization and dump stability

## Token model (practical summary)

`tokenize(input)` returns a sequence of `Token` values whose string
representation (`Token::to_string`) is compared in tests. The suite includes at
least:

- `Character('x')` tokens for character data emitted by the tokenizer.
- `EOF` as the final token.

In a full WHATWG tokenizer, token kinds include (not exhaustive):

- `StartTag(name, attrs, self_closing)`
- `EndTag(name)`
- `Comment(text)`
- `Doctype(name, public_id?, system_id?, force_quirks?)`
- `Character(ch)` / “character tokens”
- `EOF`

Even if the internal representation differs, `Token::to_string` must serialize
tokens in exactly the form expected by this repo’s tests.

## Parse errors (collection behavior)

The WHATWG parser defines many parse error conditions; the suite’s needs are:

- Errors are collected and returned by `parse_with_errors` and `tokenize`.
- Parsing/tokenization continues after errors (error-tolerant).
- Tests rarely assert exact error messages, but they do rely on errors being
  recorded in clearly malformed cases.

## Tree builder behaviors stressed by the suite

The html5lib-derived tests in this repo heavily stress:

- **Adoption agency algorithm** (mis-nested formatting elements like `<b><i>...`)
- **Implied end tags** and element scope boundaries
- **Table insertion modes** and foster parenting
- **Foreign content** (`<svg>`, `<math>`) integration points
- **Template** content behavior (`<template>` has a separate content subtree)
- **Scripting flag** effect on `<noscript>` parsing (`parse_with_scripting`)

If you implement the spec state machine literally, these behaviors fall out
naturally; ad-hoc stack fixes usually fail many cases.

## `Document::dump` canonicalization details

Because `dump()` is the primary oracle for tree construction, define:

- Node ordering:
  - children are listed in document order
  - implied elements appear where the algorithm inserts them
- Text nodes:
  - rendered as quoted strings with escaped quotes where needed
  - adjacent text nodes may be merged (or not) depending on how `dump()` is
    defined; tests define the expected behavior
- Attributes:
  - if `dump()` renders attributes, attribute ordering and quoting rules must be
    stable (tests mostly check structure and text content).

## Serialization (`Document::to_html`) expectations

The suite includes serialization checks. At minimum:

- Must produce valid HTML markup with proper escaping for text and attribute
  values (`&`, `<`, `>`, quotes in attrs).
- Must serialize implied `<html><head><body>` wrappers in the same way the tests
  expect (see `README.mbt.md` examples).

- `html5/README.mbt.md`
  - documents expected behavior for `parse`, error recovery, and serialization
