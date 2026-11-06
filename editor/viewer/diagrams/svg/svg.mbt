///|
/// Compiles one diagram to SVG. Invalid source returns `None` so the caller
/// can keep its source fallback. A host that bundles this package passes this
/// function to `@diagrams.use_bundled_renderer`.
pub fn render(kind : @diagrams.DiagramKind, source : String) -> String? {
  match kind {
    Diago => render_diago(source)
    Uml => render_uml(source)
    Mbti => render_mbti(source)
    PackageDependencies => render_package_dependencies(source)
  }
}

///|
/// Compiles a D2/Diago body.
pub fn render_diago(source : String) -> String? {
  Some(
    @diago.compile(
      source,
      options=@diago.CompileOptions::new().with_output_mode(Svg),
    ),
  ) catch {
    _ => None
  }
}

///|
/// Uses CSS-backed paint values so one UML SVG follows the host's current
/// foreground and surface colors without a theme-time rerender.
pub fn render_uml(source : String) -> String? {
  Some(@uml.render_svg(source, color_scheme=viewer_uml_color_scheme())) catch {
    _ => None
  }
}

///|
/// Compiles one generated MoonBit interface body directly to the UML
/// renderer's MBTI diagram family. The source is the `.mbti` file itself, not
/// a PlantUML wrapper.
pub fn render_mbti(source : String) -> String? {
  Some(@uml.render_mbti_svg(source, color_scheme=viewer_uml_color_scheme())) catch {
    _ => None
  }
}

///|
/// Compiles the JSON emitted by `moon tree --package --json` to a package
/// dependency SVG. The command remains the host's responsibility.
pub fn render_package_dependencies(source : String) -> String? {
  Some(
    @uml.render_package_dep_svg(source, color_scheme=viewer_uml_color_scheme()),
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
