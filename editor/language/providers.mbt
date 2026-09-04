///|
/// Hover payload shape. Markdown content is rendered by browser hover
/// participants; plaintext is escaped and shown verbatim.
pub(all) enum HoverContent {
  PlainText(String)
  Markdown(String)
} derive(Eq, Debug)

///|
/// Hover result anchored to a line/column `Range`, matching Monaco's `Hover`.
pub(all) struct Hover {
  range : @base_common.Range
  contents : Array[HoverContent]
} derive(Debug)

///|
/// One whole-line Markdown source-comment block. `line_range` uses the
/// repository's 1-based half-open line convention.
pub(all) struct MarkdownCommentBlock {
  line_range : @base_common.LineRange
  markdown : String
} derive(Eq, Debug)

///|
/// Diagnostic severity levels accepted from semantic providers. `Hint`
/// matches Monaco's `MarkerSeverity.Hint`.
pub(all) enum DiagnosticSeverity {
  Error
  Warning
  Info
  Hint
} derive(Eq, Debug)

///|
/// Diagnostic tag, mirroring Monaco's `MarkerTag` (`markers.ts:51`). Kept
/// local to `language`
/// rather than reusing `viewer/common/markers`'s `MarkerTag`, since `language`
/// sits below `viewer` in the package graph.
pub(all) enum DiagnosticTag {
  Unnecessary
  Deprecated
} derive(Eq, Debug)

///|
/// Problem marker over a source range. `range` is a line/column `Range`,
/// matching Monaco's `IMarkerData`.
pub(all) struct Diagnostic {
  range : @base_common.Range
  severity : DiagnosticSeverity
  message : String
  tags : Array[DiagnosticTag]?
} derive(Eq, Debug)

///|
/// Cross-document location result for definition and reference providers.
/// `range` is a line/column `Range`, matching Monaco's `Location`.
pub(all) struct Location {
  uri : @base_common.Uri
  range : @base_common.Range
} derive(Debug)

///|
/// Symbol outline item for the current document. `range` is a line/column
/// `Range`, matching Monaco's `DocumentSymbol`.
pub(all) struct DocumentSymbol {
  name : String
  kind : String
  range : @base_common.Range
} derive(Debug)

///|
/// Host-executable command attached to a CodeLens. Arguments remain JSON so
/// the generic editor API does not acquire a dependency on any language or
/// workbench command model.
pub(all) struct CodeLensCommand {
  id : String
  title : String
  tooltip : String?
  arguments : Array[Json]
} derive(Debug)

///|
/// One inline command row anchored to a source range. `command=None` denotes
/// a lens that may be completed by its registration's optional resolver.
pub(all) struct CodeLens {
  range : @base_common.Range
  id : String?
  command : CodeLensCommand?
} derive(Debug)

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
/// Optional completion capability registered beside a CodeLens provider.
/// Keeping it separate lets simple providers implement only the eager path.
pub(open) trait CodeLensResolver {
  async fn resolve_code_lens(
    Self,
    @model.TextModel,
    CodeLens,
    CancellationToken,
  ) -> CodeLens?
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
pub extend CodeLensCommand with Debug::{to_repr}

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
