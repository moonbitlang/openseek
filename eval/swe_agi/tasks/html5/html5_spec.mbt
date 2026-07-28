///|
/// # MoonBit HTML5 Parser - API Specification
///
/// A WHATWG-compliant HTML5 parser with tokenizer, tree builder, and serializer.
declare pub type Document

// =============================================================================
// CORE PARSING API
// =============================================================================

///|
declare pub type Element

///|
declare pub type ParseError

///|
declare pub type Token

///|
declare pub fn Token::to_string(self : Token) -> String

///|
pub impl Show for Token with fn output(token, logger) {
  logger.write_string(token.to_string())
}

///|
pub impl Debug for Token with fn to_repr(token) {
  @debug.Repr::literal(token.to_string())
}

///|
declare pub type Namespace

///|
declare pub type Node

///|
/// Parse an HTML string into a Document.
///
/// This is the main entry point for parsing HTML. The parser follows the
/// WHATWG HTML5 specification and handles malformed HTML gracefully.
///
/// Example:
/// ```
/// let doc = parse("<html><body><p>Hello</p></body></html>")
/// ```
declare pub fn parse(input : String) -> Document

///|
/// Parse HTML and return both the document and any parse errors encountered.
///
/// Use this when you need to report or log parsing errors for diagnostics.
///
/// Example:
/// ```
/// let (doc, errors) = parse_with_errors("<p>Test</p attr>")
/// // errors contains parse error information
/// ```
declare pub fn parse_with_errors(
  input : String,
) -> (Document, Array[ParseError])

///|
/// Parse HTML with scripting enabled.
///
/// When scripting is enabled, the content inside `<noscript>` tags is treated
/// as raw text rather than being parsed as HTML.
declare pub fn parse_with_scripting(input : String) -> Document

///|
/// Tokenize HTML without building a tree.
///
/// Returns an array of tokens and any parse errors. Useful for syntax
/// highlighting, linting, or custom tree construction.
///
/// Example:
/// ```
/// let (tokens, errors) = tokenize("<div>Hello</div>")
/// // tokens[0] = StartTag(name="div", ...)
/// ```
declare pub fn tokenize(input : String) -> (Array[Token], Array[ParseError])

// =============================================================================
// DOCUMENT METHODS
// =============================================================================

///|
/// Create a new empty document.
declare pub fn Document::new() -> Document

///|
/// Serialize the document to an HTML string.
///
/// Produces valid HTML5 output with proper escaping of text content
/// and attribute values.
///
/// Example:
/// ```
/// let doc = parse("<p>Hello & World</p>")
/// doc.to_html() // "<html><head></head><body><p>Hello &amp; World</p></body></html>"
/// ```
declare pub fn Document::to_html(self : Document) -> String

///|
/// Pretty-print the document tree for debugging.
///
/// Returns a human-readable indented representation of the DOM tree.
declare pub fn Document::dump(self : Document) -> String

///|
declare pub fn Document::get_body_element(self : Document) -> Int

///|
/// Get child node IDs for a given node.
declare pub fn Document::get_children(
  self : Document,
  node_id : Int,
) -> Array[Int]

///|
/// Get the parent node ID. Returns NO_NODE (-1) if no parent.
declare pub fn Document::get_parent(self : Document, node_id : Int) -> Int

///|
/// Get the tag name of an element node.
declare pub fn Document::get_tag_name(self : Document, node_id : Int) -> String?

///|
/// Get an attribute value by name.
declare pub fn Document::get_attribute(
  self : Document,
  node_id : Int,
  name : String,
) -> String?

///|
/// Check if an element has a specific attribute.
declare pub fn Document::has_attribute(
  self : Document,
  node_id : Int,
  name : String,
) -> Bool

///|
/// Set an attribute on an element.
declare pub fn Document::set_attribute(
  self : Document,
  node_id : Int,
  name : String,
  value : String,
) -> Unit

///|
/// Get the concatenated text content of a node and its descendants.
declare pub fn Document::get_text_content(
  self : Document,
  node_id : Int,
) -> String

///|
/// Get the namespace of an element node.
declare pub fn Document::get_ns(self : Document, node_id : Int) -> Namespace?

///|
/// Get the Element struct for a node, if it is an element.
declare pub fn Document::get_element(self : Document, node_id : Int) -> Element?

///|
/// Get the raw Node for a given node ID.
declare pub fn Document::get_node(self : Document, node_id : Int) -> Node?

///|
/// Check if a node is an element with the given tag name and namespace.
declare pub fn Document::is_element(
  self : Document,
  node_id : Int,
  tag_name : String,
  ns : Namespace,
) -> Bool

///|
/// Check if a node is an HTML element with the given tag name.
declare pub fn Document::is_html_element(
  self : Document,
  node_id : Int,
  tag_name : String,
) -> Bool

// =============================================================================
// DOM MANIPULATION
// =============================================================================

///|
/// Add a new node to the document. Returns the node ID.
declare pub fn Document::add_node(self : Document, node : Node) -> Int

///|
/// Append a child node to a parent node.
declare pub fn Document::append_child(
  self : Document,
  parent_id : Int,
  child_id : Int,
) -> Unit

///|
/// Insert a node before a reference node.
declare pub fn Document::insert_before(
  self : Document,
  parent_id : Int,
  new_node_id : Int,
  ref_node_id : Int,
) -> Unit

///|
/// Remove a child node from its parent.
declare pub fn Document::remove_child(
  self : Document,
  parent_id : Int,
  child_id : Int,
) -> Unit

///|
/// Get the template content node ID for a `<template>` element.
declare pub fn Document::get_template_content(
  self : Document,
  node_id : Int,
) -> Int

// =============================================================================
// ELEMENT CREATION
// =============================================================================

///|
/// Create a new Element with tag name, namespace, and attributes.
declare pub fn Element::new(
  tag_name : String,
  ns : Namespace,
  attributes : Array[(String, String)],
) -> Element
