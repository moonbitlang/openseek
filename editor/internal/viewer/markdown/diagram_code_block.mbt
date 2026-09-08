///|
/// Renders package-owned exact lowercase diagram fences before any caller
/// override. `d2`/`diago` use Diago, while `uml`/`plantuml` use the UML
/// renderer. Unknown, unlabelled, and failed diagram blocks keep the existing
/// fallback.
///
/// ```d2
/// direction: right
///
/// fence: fenced block
/// language: supported diagram fence?
/// compile: matching compiler to SVG
/// wrapper: diagram wrapper
/// fallback: ordinary code HTML
///
/// fence -> language
/// language -> compile: yes
/// language -> fallback: no
/// compile -> wrapper: success
/// compile -> fallback: failure
/// ```
fn render_diagram_code_block(code_block : MarkdownCodeBlock) -> String? {
  match code_block.language_id {
    Some("diago") | Some("d2") =>
      render_diago_svg(code_block.code).map(svg => {
        wrap_diagram_svg("diago", svg)
      })
    Some("uml") | Some("plantuml") =>
      render_uml_diagram_svg(code_block.code).map(svg => {
        wrap_diagram_svg("uml", svg)
      })
    _ => None
  }
}

///|
/// Compile a D2/Diago body for Markdown documents or standalone consumers.
/// Failed compilation leaves the consumer responsible for its source fallback.
pub fn render_diago_svg(source : String) -> String? {
  let svg = @diago.compile(
    source,
    options=@diago.CompileOptions::new().with_output_mode(Svg),
  ) catch {
    _ => return None
  }
  Some(svg)
}

///|
/// Uses CSS-backed paint values so one synchronous UML SVG follows the host's
/// current foreground and surface colors without a theme-time rerender.
pub fn render_uml_diagram_svg(source : String) -> String? {
  let color_scheme = viewer_uml_color_scheme()
  Some(@uml.render_svg(source, color_scheme~)) catch {
    _ => None
  }
}

///|
/// Compile one generated MoonBit interface body directly to the UML
/// renderer's MBTI diagram family. The source is the `.mbti` file itself, not
/// a PlantUML wrapper; malformed interfaces stay on the caller's fallback
/// path.
pub fn render_mbti_diagram_svg(source : String) -> String? {
  let color_scheme = viewer_uml_color_scheme()
  Some(@uml.render_mbti_svg(source, color_scheme~)) catch {
    _ => None
  }
}

///|
/// Compile the JSON emitted by `moon tree --package --json` to a package
/// dependency SVG. The command remains the host's responsibility; this pure
/// boundary only renders its successful output and keeps malformed graphs on
/// the caller's fallback path.
pub fn render_package_dep_diagram_svg(source : String) -> String? {
  let color_scheme = viewer_uml_color_scheme()
  Some(@uml.render_package_dep_svg(source, color_scheme~)) catch {
    _ => None
  }
}

///|
/// Keep every synchronous UML surface on the same CSS-backed palette. SVGs
/// can then follow a host theme change without recompiling their source.
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

///|
fn wrap_diagram_svg(language_id : String, svg : String) -> String {
  (
    $|<div class="moonbit-viewer-markdown-diagram" data-diagram-language="\{language_id}">
    $|\{svg}
    $|</div>
    $|
  )
}
