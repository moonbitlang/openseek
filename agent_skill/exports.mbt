// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// One-line summary the model uses to decide relevance, from frontmatter
/// `description:` (empty when the file declares none).
pub fn Skill::description(self : Skill) -> String {
  self.description
}

///|
/// The skill's short identifier, from frontmatter `name:` or the file stem.
pub fn Skill::name(self : Skill) -> String {
  self.name
}

///|
/// Path of the markdown file holding the full skill body.
pub fn Skill::path(self : Skill) -> String {
  self.path
}
