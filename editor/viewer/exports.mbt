// Staged host API: the Desktop GitHub review integration consumes these
// after this independently tested editor capability lands.

///|
/// A host-rendered DOM block anchored after a line on either diff side.
/// on_layout receives Some((client left, top, width)), or None when hidden. The
/// host retains DOM ownership; the editor reserves and measures its space.
/// In unified layout an original-side block follows its deleted hunk. Keep
/// node identity stable across content edits so native focus is preserved.
pub(all) struct DiffLineWidget {
  original : Bool
  line : Int
  node : @rdom.Element
  on_layout : ((Double, Double, Double)?) -> Unit
}

///|
pub fn DiffEditor::set_line_widgets(
  self : DiffEditor,
  widgets : Array[DiffLineWidget],
) -> Unit {
  self.widget.set_line_widgets(
    widgets.map(widget => {
      original: widget.original,
      line: widget.line,
      node: widget.node,
      on_layout: widget.on_layout,
    }),
  )
}

///|
/// Install an action for the hovered model line (original side, line number).
/// The callback is host policy; no comment or remote-service state is stored.
pub fn DiffEditor::set_line_action(
  self : DiffEditor,
  action : ((Bool, Int) -> Unit)?,
) -> Unit {
  self.widget.set_line_action(action)
}

///|
/// Permit unified layout below the host's minimum usable split width.
pub fn DiffEditorOptions::with_automatic_inline(
  self : DiffEditorOptions,
  enabled : Bool,
  width? : Double = 900.0,
) -> DiffEditorOptions {
  { ..self, automatic_inline: enabled, automatic_inline_width: width, }
}
