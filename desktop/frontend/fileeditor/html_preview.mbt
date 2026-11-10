///|
pub fn is_html_file(path : String) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".html") || lower.has_suffix(".htm")
}

///|
pub fn Ctx::can_preview_html(self : Ctx, desktop~ : Bool) -> Bool {
  match self.owner {
    Cloud(..) => self.root() is Some(_)
    Host({ channel: Local, .. }) => desktop
    Host(_) => false
  }
}
