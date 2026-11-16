///|
/// Compiles one diagram to SVG. Invalid source returns `None` so the caller
/// can keep its source fallback. A host that bundles this package passes this
/// function to `@diagrams.use_bundled_renderer`.
///
/// UML-family diagrams use CSS-backed paint values, so one SVG follows the
/// host's current foreground and surface colors without a theme-time
/// rerender. `Mbti` takes a generated `.mbti` body itself, not a PlantUML
/// wrapper; `PackageDependencies` takes the JSON emitted by
/// `moon tree --package --json`.
pub fn render(kind : @diagrams.DiagramKind, source : String) -> String? {
  let color_scheme = viewer_uml_color_scheme()
  Some(
    match kind {
      Diago =>
        @diago.compile(
          source,
          options=@diago.CompileOptions::new().with_output_mode(Svg),
        )
      Uml => @uml.render_svg(source, color_scheme~)
      Mbti => @uml.render_mbti_svg(source, color_scheme~)
      PackageDependencies => @uml.render_package_dep_svg(source, color_scheme~)
    },
  ) catch {
    _ => None
  }
}

///|
/// Keep every UML surface on the same CSS-backed palette. SVGs can then
/// follow a host theme change without recompiling their source.
fn viewer_uml_color_scheme() -> @uml_style.ColorScheme {
  let foreground = "var(--vscode-editor-foreground, #1f2328)"
  let muted = "var(--vscode-descriptionForeground, #6e7781)"
  let surface = "var(--vscode-editorWidget-background, var(--vscode-editor-background, #ffffff))"
  let note_surface = "var(--vscode-editorHoverWidget-background, var(--vscode-editorWidget-background, #fff8c5))"
  ColorScheme(
    foreground,
    foreground,
    canvas="none",
    node=surface,
    note=note_surface,
    partition="none",
    participant=surface,
    activation=surface,
    lifeline=muted,
    divider=muted,
    divider_title=surface,
    delay=muted,
    reference_tab=surface,
    page_break=muted,
    transparent="none",
  )
}
