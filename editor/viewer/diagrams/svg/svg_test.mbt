///|
test "UML renderer returns SVG only for valid diagrams" {
  let valid =
    #|@startuml
    #|participant Alice
    #|Alice -> Bob : hello
    #|@enduml
  guard @svg.render_uml(valid) is Some(svg) else { fail("expected UML SVG") }
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("--vscode-editor-foreground"))
  // UML 0.4.3 treats a bare `@startuml`/`@enduml` pair as a valid empty
  // sequence diagram, so it renders a diagram with no content.
  guard @svg.render_uml("@startuml\n@enduml") is Some(empty_svg) else {
    fail("expected an empty UML SVG")
  }
  assert_true(empty_svg.contains("<svg"))
  assert_true(empty_svg.contains("aria-label=\"Sequence diagram\""))
  assert_false(empty_svg.contains("<g"))
  assert_true(@svg.render_uml("@startuml\n@@@\n@enduml") is None)
}

///|
test "MBTI renderer accepts a bare generated interface" {
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
  guard @svg.render_mbti(source) is Some(svg) else { fail("expected MBTI SVG") }
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("Point"))
  assert_true(svg.contains("--vscode-editor-foreground"))
  assert_true(@svg.render_mbti("pub struct MissingPackage") is None)
}

///|
test "package dependency renderer accepts moon tree JSON" {
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
  guard @svg.render_package_dependencies(source) is Some(svg) else {
    fail("expected package dependency SVG")
  }
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("main"))
  assert_true(svg.contains("core"))
  assert_true(svg.contains("util"))
  assert_true(svg.contains("--vscode-editor-foreground"))
  assert_true(@svg.render_package_dependencies("{\"nodes\":[]}") is None)
}

///|
test "Diago renderer preserves invalid source fallback" {
  guard @svg.render_diago("a -> b") is Some(svg) else {
    fail("expected Diago SVG")
  }
  assert_true(svg.contains("<svg"))
  assert_true(@svg.render_diago("a ->") is None)
}

///|
test "render dispatches each diagram kind to its renderer" {
  assert_true(@svg.render(Diago, "a -> b") is Some(_))
  assert_true(@svg.render(Uml, "@startuml\nA -> B\n@enduml") is Some(_))
  assert_true(@svg.render(Mbti, "pub struct MissingPackage") is None)
  assert_true(@svg.render(PackageDependencies, "{\"nodes\":[]}") is None)
}
