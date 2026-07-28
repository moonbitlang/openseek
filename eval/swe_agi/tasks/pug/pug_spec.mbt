///|
/// Spec-driven API contract for a Pug template engine.
///
/// This package intentionally provides declaration-only function stubs.
/// Implementations should be added in new `.mbt` files in this directory.

///|
declare pub(all) type Document

///|
/// Encode the parsed AST for tests.
///
/// The expected shape is driven by tests using `json_inspect`.
declare pub fn Document::to_test_json(self : Document) -> Json

///|
/// Convenience for tests that only need to know whether any top-level nodes exist.
declare pub fn Document::node_count(self : Document) -> Int

///|
declare pub(all) type Locals

///|
declare pub fn Locals::new() -> Locals

///|
declare pub fn Locals::set(self : Locals, key : String, value : String) -> Unit

///|
declare pub fn Locals::set_array(
  self : Locals,
  key : String,
  value : Array[String],
) -> Unit

///|
declare pub fn Locals::set_nested_array(
  self : Locals,
  key : String,
  value : Array[Array[String]],
) -> Unit

///|
declare pub fn Locals::set_object(
  self : Locals,
  key : String,
  value : Map[String, String],
) -> Unit

///|
declare pub(all) type TemplateRegistry

///|
declare pub fn TemplateRegistry::new() -> TemplateRegistry

///|
declare pub fn TemplateRegistry::register(
  self : TemplateRegistry,
  path : String,
  template : String,
) -> Unit

///|
declare pub(all) type CompiledTemplate

///|
declare pub fn CompiledTemplate::render(
  self : CompiledTemplate,
  locals : Locals,
) -> String

///|
/// Parse Pug into an AST document.
declare pub fn parse(input : String) -> Document

///|
/// Parse with a registry (resolves include/extends during parsing when needed by tests).
declare pub fn parse_with_registry(
  input : String,
  registry : TemplateRegistry,
) -> Document

///|
/// Render Pug into compact HTML.
declare pub fn render(input : String) -> String

///|
/// Render Pug into pretty-printed HTML.
declare pub fn render_pretty(input : String) -> String

///|
/// Render Pug with locals for interpolation/conditionals/loops.
declare pub fn render_with_locals(input : String, locals : Locals) -> String

///|
/// Render Pug with a registry for include/extends resolution.
declare pub fn render_with_registry(
  input : String,
  locals : Locals,
  registry : TemplateRegistry,
) -> String

///|
/// Render a file from disk.
declare pub fn render_file(path : String) -> String raise @fs.IOError

///|
/// Render a file from disk with locals.
declare pub fn render_file_with_locals(
  path : String,
  locals : Locals,
) -> String raise @fs.IOError

///|
/// Compile a template for repeated rendering.
declare pub fn compile(input : String) -> CompiledTemplate

///|
/// Evaluate a JavaScript expression (JS backend only).
declare pub fn eval_js_expression(expr : String, locals : Locals) -> String
