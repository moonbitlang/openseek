///|
/// Reveal a recorded modified-side line once the current comparison is ready.
/// Clamp to the current document bounds without snapping to a changed hunk.
/// Staged host contract: Desktop transcript navigation adopts this in #1681.
pub fn DiffEditor::reveal_modified_line(self : DiffEditor, line : Int) -> Unit {
  self.widget.reveal_modified_line(line)
}
