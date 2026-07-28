# Pug (Jade) template engine — specification for this repo

This document is a **practical, test-oriented spec** for the `pug`
package. It summarizes the Pug language subset and rendering behaviors required
by this repository’s MoonBit API and test corpus (including a large generated
suite derived from pugjs).

It is **not** a verbatim copy of the upstream Pug documentation, and it does not
attempt to fully standardize Pug (which evolves with pugjs). In this repository,
the test suite is the source of truth for observable behavior.

## Objectives (what the implementation must do)

The `pug` package expects an implementation that can:

1. Parse Pug source into an AST `Document` (`parse` / `parse_with_registry`).
2. Render Pug into HTML:
   - compact (`render`, `render_with_locals`, `render_with_registry`)
   - pretty (`render_pretty`)
3. Support locals for interpolation, conditionals, loops, and simple JS
   evaluation used by Pug (JS backend is required by this repo).
4. Support include/extends via a registry (`TemplateRegistry`) and/or file IO.
5. Produce a stable JSON encoding of the AST via `Document::to_test_json()` for
   snapshot-style tests.

## Primary references

- Pug docs (language reference): https://pugjs.org/
- Pug GitHub (source + tests): https://github.com/pugjs/pug

The provided suite encodes many pugjs “cases/…” fixtures; treat it as canonical
behavior for covered features.

## Scope and explicit non-goals

### Scope (features heavily exercised by tests)

From the provided test corpus:

- Indentation-based nesting (significant whitespace).
- Tag syntax:
  - `div`, `p`, etc.
  - inline tags and nesting
  - self-closing tags behavior as exercised by tests
- Text:
  - inline text after tag name
  - piped text blocks (`| ...`)
  - block text with dot (`p.`)
  - `pre`/whitespace-preserving cases
- Attributes:
  - parentheses form `a(href="#")`
  - boolean-like attributes per fixtures
  - unescaped attribute values where tested
- IDs/classes shorthand: `#id`, `.class`, combinations
- Doctype handling (default + keyword/custom doctypes)
- Comments:
  - HTML comments and “silent” comments per fixtures
- Code:
  - unbuffered code (`- var x = ...`)
  - buffered code (`p= expr`)
  - conditionals (`if/else`)
  - iteration (`each`, `while`) as exercised by cases
- Interpolation:
  - escaped `#{expr}`
  - unescaped `!{expr}`
- Mixins and blocks:
  - mixin definitions/calls, attributes, blocks, rest args (as in fixtures)
  - template inheritance: `extends`, `block`, `append`, `prepend`, `yield`
- Includes:
  - include relative paths, include-only-text cases
  - include with filters (as exercised)
- Filters:
  - inline filters and filter-in-include cases (fixture-driven)

### Non-goals

- Full JS execution environment parity with Node.js beyond what tests require.
- Supporting every Pug option/flag from pugjs (compile-time options).
- Security hardening for untrusted templates (not the focus of this suite).

## API contract (from `pug/pug_spec.mbt`)

### Parsing and AST inspection

- `parse(input : String) -> Document`
- `parse_with_registry(input : String, registry : TemplateRegistry) -> Document`
- `Document::to_test_json(self) -> Json`
- `Document::node_count(self) -> Int`

### Rendering

- `render(input : String) -> String`
- `render_pretty(input : String) -> String`
- `render_with_locals(input : String, locals : Locals) -> String`
- `render_with_registry(input : String, locals : Locals, registry : TemplateRegistry) -> String`
- `render_file(path : String) -> String raise @fs.IOError`
- `render_file_with_locals(path : String, locals : Locals) -> String raise @fs.IOError`

### Compilation

- `compile(input : String) -> CompiledTemplate`
- `CompiledTemplate::render(self, locals : Locals) -> String`

### Locals and registry

- `Locals::new()`, `set`, `set_array`, `set_nested_array`, `set_object`
- `TemplateRegistry::new()`, `register(path, template)`

### JS expression evaluation (JS backend only)

- `eval_js_expression(expr : String, locals : Locals) -> String`

Important repo constraint (from `TASK.md`):

- Tests must pass under target `js` (use JS as preferred target).

## Source model: lines, indentation, blocks

### Significant indentation

- Indentation defines nesting, similar to Python/YAML.
- A line is a node (tag, text, code, etc.); indented following lines become its
  children (depending on node type).
- Tabs/spaces mixing rules are fixture-driven; prefer pugjs-compatible behavior.

### Inline vs block content

Some constructs take inline content on the same line:

- `p hello` (tag + inline text)
- `p= expr` (tag + buffered code)
- `a(href="#") here` (tag + attrs + inline text)

Other constructs introduce a block:

- `p` followed by indented child lines
- `p.` followed by indented raw text block
- piped text lines (`| ...`) as children

## Text and escaping rules (critical)

### Plain text nodes

Text produced as literal text in the template must be HTML-escaped by default
when inserted into the HTML output, except in contexts where Pug defines raw
text or unescaped interpolation is used.

Example from tests:

- Source: `p This is plain old <em>text</em> content.`
- Output: `<p>This is plain old &lt;em&gt;text&lt;/em&gt; content.</p>`

### Escaped vs unescaped interpolation

Pug has two interpolation forms:

- `#{expr}`: evaluate expr and **escape** it for HTML insertion.
- `!{expr}`: evaluate expr and insert **unescaped** (raw HTML).

The suite includes:

- `p #{msg.toUpperCase()}` (escaped interpolation)
- `p Joel: !{riskyBusiness}` (unescaped interpolation of HTML string)

### Entity handling

Literal text must escape at least:

- `&` → `&amp;`
- `<` → `&lt;`
- `>` → `&gt;`
- `"` → `&quot;` (when in attribute values)
- `'` → `&#39;` or `&apos;` (fixture-defined; output must match expected)

Treat the expected HTML snapshots as canonical for the exact escaping.

## Tags, attributes, ids/classes

### Tag syntax

- A bare tag name starts an element node: `div`, `p`, `a`, etc.
- If no tag is provided but an id/class is present (e.g. `.quote`), Pug defaults
  to a `div` element (this is exercised by fixtures).

### ID and class shorthands

- `#id` sets the element id.
- `.class` appends a class.
- Multiple classes accumulate in order; exact ordering in serialization is
  fixture-driven.

### Attributes

Attributes are written as:

- `a(href="#")`
- `div(data-value=count + 1)`

Key points:

- Attribute values may be:
  - quoted strings
  - JS expressions (evaluated under JS backend, see below)
- The output must quote attribute values with `"` in HTML as fixtures expect.
- Attribute escaping depends on whether it is marked unescaped by Pug syntax
  (fixtures include `attrs.unescaped`).

## Code evaluation (JS backend requirement)

Pug uses JavaScript as its expression language. This repo requires the JS
backend tests, including explicit expression evaluation, to pass.

### `eval_js_expression`

This function must evaluate a JavaScript expression against `locals` and return
the string result.

Examples from tests:

- locals: `{x: "5"}` expr: `x + 1` → `"6"` (numeric addition under JS coercion)
- locals: `{s: "hello"}` expr: `s.toUpperCase()` → `"HELLO"`

### Template code forms

Fixtures exercise:

- unbuffered JS code: `- var msg = "hello"`
- buffered expression: `p= active ? ... : ...`
- interpolation expressions: `#{...}` and `!{...}`
- attribute expressions: `div(data-value=count + 1)`

Implementation note:

- Locals are stored as strings/arrays/maps in `Locals`; JS evaluation must map
  these into JS values in a way that matches fixtures (arrays as arrays, objects
  as objects, booleans/numbers where the suite expects JS coercion behavior).

## Includes, extends, and registries

### Registry-based resolution

`TemplateRegistry` maps `path -> template text` for:

- `include path`
- `extends path`

`render_with_registry` / `parse_with_registry` should use the registry to
resolve referenced templates, with relative path rules matching the generated
fixtures (`include-extends-relative`, `include-extends-from-root`, etc.).

### File-based resolution

`render_file*` must read from disk and resolve relative includes/extends based
on the calling file’s directory (fixture-driven; tests may cover).

## AST JSON encoding (`Document::to_test_json`)

The suite uses `Document::to_test_json()` as an oracle for parsing behavior in
hand-written tests.

The expected shape is:

- Top-level: `{ "nodes": [ <node>, <node>, ... ] }`
- Nodes are tagged arrays like:
  - `["Text", "text content"]`
  - `["Element", { "tag": "...", "id": "...", "classes": [...], "attributes": [...], "children": [...], "self_closing": false }]`

Attributes appear as objects like:

- `{ "name": "href", "value": "#", "unescaped": false }`

Exact JSON shape is fixture-driven; implementations should ensure stable field
ordering and deterministic output.

## Pretty vs compact rendering

`render` produces compact HTML (no pretty whitespace beyond what is required by
the template).

`render_pretty` produces pretty-printed HTML. The exact formatting rules are
fixture-driven; at minimum:

- stable indentation
- newlines between elements in a readable structure

If fixtures only assert compact output, pretty printing may be lightly tested,
but the API exists and should be implemented.
