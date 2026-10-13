///|
fn Model::can_attach_pdf_capture(self : Model) -> Bool {
  let input = match self.quote_screen() {
    Some(ChatQuote) => self.composer_input()
    Some(CodexQuote) => self.codex_composer_input()
    None => return false
  }
  input.quote_target() is Some(_) && input.presentation.images_enabled
}
