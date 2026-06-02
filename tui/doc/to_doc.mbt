///|
/// Projection of a semantic value into a renderable `Doc`.
///
/// The styled-text vocabulary lives here, but the values that know how to render
/// themselves into it (transcript items, inputs) live in higher layers. Defining
/// the trait here lets those layers attach the projection to their own types —
/// the orphan rule allows the `impl` in the type's own package — and lets any
/// importer of `doc` project a value uniformly via `@doc.ToDoc::to_doc(value)`.
pub(open) trait ToDoc {
  fn to_doc(Self) -> Doc
}
