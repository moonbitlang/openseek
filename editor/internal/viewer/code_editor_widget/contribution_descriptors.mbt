///|
/// Typed identity of one contribution description in the process-wide editor
/// registry. This is deliberately not an editor "role": construction selects
/// an immutable set of independent capabilities, and runtime feature code
/// discovers availability from the installed contribution itself.
priv enum CodeEditorContributionKind {
  AgentFeedbackInput
  AgentFeedbackWidget
  Folding
  MarkdownComments
  ContentHover
  QuickDiff
  ContextMenu
  Definition
  References
  CodeLens
} derive(Eq)

///|
/// Explicit contribution set for one code-editor kernel. The fields stay
/// opaque outside this package so hosts choose a reviewed factory rather than
/// rebuilding a second contribution policy from booleans or editor roles.
pub struct CodeEditorContributionDescriptors {
  priv enabled : Array[CodeEditorContributionKind]
}

///|
fn CodeEditorContributionDescriptors::from_enabled(
  enabled : Array[CodeEditorContributionKind],
) -> CodeEditorContributionDescriptors {
  { enabled, }
}

///|
fn CodeEditorContributionDescriptors::allows(
  self : CodeEditorContributionDescriptors,
  kind : CodeEditorContributionKind,
) -> Bool {
  self.enabled.contains(kind)
}

///|
/// Full standalone code-editor surface. This is the public `Viewer` policy:
/// all ordinary code contributions, including Markdown-comment projection and
/// source-control quick diff, are available.
pub fn CodeEditorContributionDescriptors::standalone() -> CodeEditorContributionDescriptors {
  CodeEditorContributionDescriptors::from_enabled([
    AgentFeedbackInput,
    AgentFeedbackWidget,
    Folding,
    MarkdownComments,
    ContentHover,
    QuickDiff,
    ContextMenu,
    Definition,
    References,
    CodeLens,
  ])
}

///|
/// Diff-pane code-editor surface. It keeps ordinary navigation, hover,
/// context menu, references, and agent feedback. The folding controller is
/// excluded; DiffEditor disables its option and independently reserves the
/// shared decorations lane for comment and feedback controls.
/// Markdown-comment replacement remains installed so the diff coordinator can
/// keep it live in both SideBySide panes and suppress only the clipped Inline
/// original. Quick diff is excluded because a diff pane must not host a nested
/// SCM diff; CodeLens is standalone-only in the initial feature slice.
pub fn CodeEditorContributionDescriptors::diff_pane() -> CodeEditorContributionDescriptors {
  CodeEditorContributionDescriptors::from_enabled([
    AgentFeedbackInput,
    AgentFeedbackWidget,
    MarkdownComments,
    ContentHover,
    ContextMenu,
    Definition,
    References,
  ])
}

///|
/// Embedded Definition/References Peek preview. The preview retains hover,
/// context actions, and direct Go to Definition, but intentionally has no
/// References controller, Markdown-comment replacement, quick diff, folding,
/// CodeLens, or agent-feedback UI. In particular, Alt/Shift+F12 cannot
/// recursively open another Peek because no References contribution exists in
/// this kernel.
pub fn CodeEditorContributionDescriptors::peek_preview() -> CodeEditorContributionDescriptors {
  CodeEditorContributionDescriptors::from_enabled([
    ContentHover,
    ContextMenu,
    Definition,
  ])
}
