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

///|
test "public Viewer MBTI renderer accepts a bare generated interface" {
  let source =
    #|package "example/geometry"
    #|
    #|pub struct Point {
    #|  x : Double
    #|  y : Double
    #|}
    #|
    #|pub trait Shape {
    #|  area(Self) -> Double
    #|}
    #|
    #|impl Shape for Point
  guard render_mbti_diagram_svg(source) is Some(svg) else {
    fail("expected MBTI SVG")
  }
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("Point"))
  assert_true(svg.contains("--vscode-editor-foreground"))
  assert_true(render_mbti_diagram_svg("pub struct MissingPackage") is None)
}

///|
test "public Viewer package dependency renderer accepts moon tree JSON" {
  // The UML renderer's default filter selects nodes with in/out degree above
  // one, so this fixture deliberately branches at `main` and exercises the
  // default rather than overriding product behavior in the test.
  let source =
    #|{
    #|  "version": 2,
    #|  "status": "success",
    #|  "error": null,
    #|  "root": [0],
    #|  "nodes": [
    #|    {"module":"example/app","version":"0.1.0","source":{"kind":"local","path":"/workspace/app"},"rel":"main"},
    #|    {"module":"example/lib","version":"0.1.0","source":{"kind":"local","path":"/workspace/lib"},"rel":"core"},
    #|    {"module":"example/lib","version":"0.1.0","source":{"kind":"local","path":"/workspace/lib"},"rel":"util"}
    #|  ],
    #|  "edges": [
    #|    {"from":0,"to":1,"alias":"core","kinds":["source"]},
    #|    {"from":0,"to":2,"alias":"util","kinds":["source"]}
    #|  ],
    #|  "logs": []
    #|}
  guard render_package_dep_diagram_svg(source) is Some(svg) else {
    fail("expected package dependency SVG")
  }
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("main"))
  assert_true(svg.contains("core"))
  assert_true(svg.contains("util"))
  assert_true(svg.contains("--vscode-editor-foreground"))
  assert_true(render_package_dep_diagram_svg("{\"nodes\":[]}") is None)
}

///|
test "public Viewer Diago renderer preserves invalid source fallback" {
  guard render_diago_diagram_svg("a -> b") is Some(svg) else {
    fail("expected Diago SVG")
  }
  assert_true(svg.contains("<svg"))
  assert_true(render_diago_diagram_svg("a ->") is None)
}
