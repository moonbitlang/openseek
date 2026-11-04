///|
/// Hover payload shape. Markdown content is rendered by browser hover
/// participants; plaintext is escaped and shown verbatim.
#derive(Eq, Debug)
pub(all) enum HoverContent {
  PlainText(String)
  Markdown(String)
}

///|
/// Hover result anchored to a line/column `Range`, matching Monaco's `Hover`.
#derive(Debug)
pub(all) struct Hover {
  range : @base_common.Range
  contents : Array[HoverContent]
}

///|
/// One whole-line Markdown source-comment block. `line_range` uses the
/// repository's 1-based half-open line convention.
#derive(Eq, Debug)
pub(all) struct MarkdownCommentBlock {
  line_range : @base_common.LineRange
  markdown : String
}

///|
/// Diagnostic severity levels accepted from semantic providers. `Hint`
/// matches Monaco's `MarkerSeverity.Hint`.
#derive(Eq, Debug)
pub(all) enum DiagnosticSeverity {
  Error
  Warning
  Info
  Hint
}

///|
/// Diagnostic tag, mirroring Monaco's `MarkerTag` (`markers.ts:51`). Kept
/// local to `language`
/// rather than reusing `viewer/common/markers`'s `MarkerTag`, since `language`
/// sits below `viewer` in the package graph.
#derive(Eq, Debug)
pub(all) enum DiagnosticTag {
  Unnecessary
  Deprecated
}

///|
/// Problem marker over a source range. `range` is a line/column `Range`,
/// matching Monaco's `IMarkerData`.
#derive(Eq, Debug)
pub(all) struct Diagnostic {
  range : @base_common.Range
  severity : DiagnosticSeverity
  message : String
  tags : Array[DiagnosticTag]?
}

///|
/// Cross-document location result for definition and reference providers.
/// `range` is a line/column `Range`, matching Monaco's `Location`.
#derive(Debug)
pub(all) struct Location {
  uri : @base_common.Uri
  range : @base_common.Range
  // None when the provider does not classify test references.
  is_test : Bool?
}

///|
/// Symbol outline item for the current document. `range` is a line/column
/// `Range`, matching Monaco's `DocumentSymbol`.
#derive(Debug)
pub(all) struct DocumentSymbol {
  name : String
  kind : String
  range : @base_common.Range
}

///|
/// A complete inline action. The provider owns execution and its captured
/// data; the editor cancels the request token when this result becomes stale.
#derive(Debug)
pub(all) struct CodeLens {
  range : @base_common.Range
  title : String
  tooltip : String?
  execute : async () -> Unit noraise
}

///|
/// Asynchronous hover provider for a readonly text model and the repository's
/// one-based UTF-16 `Position`.
pub(open) trait HoverProvider {
  async fn provide_hover(
    Self,
    @model.TextModel,
    @base_common.Position,
    CancellationToken,
  ) -> Hover?
}

///|
/// Asynchronous definition provider for a readonly text model.
pub(open) trait DefinitionProvider {
  async fn provide_definition(
    Self,
    @model.TextModel,
    @base_common.Position,
    CancellationToken,
  ) -> Array[Location]
}

///|
/// Document symbol provider for outline/navigation views.
pub(open) trait DocumentSymbolProvider {
  async fn provide_document_symbols(Self, @model.TextModel, CancellationToken) -> Array[
    DocumentSymbol,
  ]
}

///|
/// Asynchronous CodeLens provider for a readonly text model.
pub(open) trait CodeLensProvider {
  async fn provide_code_lenses(Self, @model.TextModel, CancellationToken) -> Array[
    CodeLens,
  ]
}

///|
/// Synchronous provider for whole-line Markdown source comments. The caller
/// normalizes ranges and content before rendering.
pub(open) trait MarkdownCommentProvider {
  fn provide_markdown_comments(Self, @model.TextModel) -> Array[
    MarkdownCommentBlock,
  ] raise
}

///|
/// Human-readable diagnostic severity label.
pub fn DiagnosticSeverity::label(self : DiagnosticSeverity) -> String {
  match self {
    Error => "Error"
    Warning => "Warning"
    Info => "Info"
    Hint => "Hint"
  }
}

///|
/// Diagnostic tag label, mirrored on the wire.
pub fn DiagnosticTag::label(self : DiagnosticTag) -> String {
  match self {
    Unnecessary => "Unnecessary"
    Deprecated => "Deprecated"
  }
}

///|
pub extend Diagnostic with Debug::{to_repr}

///|
pub extend CodeLens with Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend DiagnosticSeverity with Debug::{to_repr}

///|
pub extend DiagnosticSeverity with Eq::{equal, not_equal}

///|
pub extend DiagnosticTag with Debug::{to_repr}

///|
pub extend DiagnosticTag with Eq::{equal, not_equal}

///|
pub extend DocumentSymbol with Debug::{to_repr}

///|
pub extend Hover with Debug::{to_repr}

///|
pub extend HoverContent with Debug::{to_repr}

///|
pub extend HoverContent with Eq::{equal, not_equal}

///|
pub extend Location with Debug::{to_repr}

///|
pub extend MarkdownCommentBlock with Debug::{to_repr}

///|
pub extend MarkdownCommentBlock with Eq::{equal, not_equal}
