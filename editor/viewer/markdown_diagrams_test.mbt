///|
test "public Viewer UML renderer returns SVG only for valid diagrams" {
  let valid =
    #|@startuml
    #|participant Alice
    #|Alice -> Bob : hello
    #|@enduml
  guard render_uml_diagram_svg(valid) is Some(svg) else {
    fail("expected UML SVG")
  }
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("--vscode-editor-foreground"))
  assert_true(render_uml_diagram_svg("@startuml\n@enduml") is None)
}
