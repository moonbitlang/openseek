///|
fn run(
  index : Int32,
  text : String,
  x : Double,
  y : Double,
  marked_id? : String,
  vertical~ : Bool = false,
  font~ : String = "font",
  has_eol~ : Bool = false,
) -> @selection.TextRun {
  {
    index,
    text,
    bounds: { x, y, width: 10, height: 10, },
    marked_id,
    vertical,
    font,
    has_eol,
  }
}

///|
fn content(id : String) -> @selection.Structure {
  { content_id: Some(id), role: None, children: [], }
}

///|
fn paragraph(id : String) -> @selection.Structure {
  { content_id: None, role: Some("P"), children: [content(id)], }
}

///|
let page : @selection.Rect = { x: 0, y: 0, width: 300, height: 300, }

///|
test "smallest tagged blocks remain separate even with the same role" {
  let tree : @selection.Structure = {
    content_id: None,
    role: Some("P"),
    children: [paragraph("a"), paragraph("b")],
  }
  let targets = @selection.targets(
    [
      run(0, "First", 10, 10, marked_id="a"),
      run(1, "Second", 22, 10, marked_id="b"),
    ],
    Some(tree),
    page,
  )
  assert_eq(targets.length(), 2)
  assert_eq(targets[0].text, "First")
  assert_eq(targets[1].text, "Second")
}

///|
test "untagged text groups by line font size and distance without crossing columns" {
  let targets = @selection.targets(
    [
      run(0, "Hello", 10, 10),
      run(1, "world", 23, 10),
      run(2, "column", 100, 10),
      run(3, "next", 10, 30),
      run(4, "font", 23, 30, font="other"),
    ],
    None,
    page,
  )
  assert_eq(targets.length(), 4)
  assert_eq(targets[0].text, "Hello world")
  assert_eq(targets[0].bounds, { x: 8, y: 8, width: 27, height: 14, })
}

///|
test "tagged text keeps content order and inserts line breaks from geometry" {
  let targets = @selection.targets(
    [
      run(2, "third", 10, 30, marked_id="a"),
      run(1, "second", 23, 10, marked_id="a"),
      run(0, "first", 10, 10, marked_id="a"),
    ],
    Some(paragraph("a")),
    page,
  )
  assert_eq(targets.length(), 1)
  assert_eq(targets[0].text, "first second\nthird")
}

///|
test "text joining preserves Unicode whitespace and explicit EOL without duplication" {
  let targets = @selection.targets(
    [
      run(0, "\ufeff你好\u00a0", 10, 10, marked_id="a"),
      run(1, "🌙", 25, 10, marked_id="a", has_eol=true),
      run(2, "下一行\u3000", 10, 30, marked_id="a"),
      run(3, " \ufeff\u3000", 80, 80),
    ],
    Some(paragraph("a")),
    page,
  )
  assert_eq(targets.length(), 1)
  assert_eq(targets[0].text, "你好\u00a0🌙\n下一行")
}

///|
test "vertical runs join along Y and remain separate from horizontal runs" {
  let targets = @selection.targets(
    [
      run(0, "A", 10, 10, vertical=true),
      run(1, "B", 10, 23, vertical=true),
      run(2, "C", 10, 23),
    ],
    None,
    page,
  )
  assert_eq(targets.length(), 2)
  assert_eq(targets[0].text, "C")
  assert_eq(targets[1].text, "A B")
  assert_true(@selection.vertical_text(1, 0, 90))
  assert_true(!@selection.vertical_text(0, 1, 270))
}

///|
test "target padding clips at page boundaries and empty runs are ignored" {
  let targets = @selection.targets(
    [run(0, "x", 0, 0), run(1, "", 20, 20)],
    None,
    { x: 0, y: 0, width: 10, height: 10, },
  )
  assert_eq(targets.length(), 1)
  assert_eq(targets[0].bounds, { x: 0, y: 0, width: 10, height: 10, })
}

///|
test "hit testing prefers smallest target and preserves order on equal areas" {
  let big : @selection.Target = {
    bounds: { x: 0, y: 0, width: 100, height: 100, },
    text: "big",
  }
  let small : @selection.Target = {
    bounds: { x: 10, y: 10, width: 10, height: 10, },
    text: "small",
  }
  let equal : @selection.Target = { ..small, text: "later", }
  assert_eq(
    @selection.hit_target([big, small, equal], { x: 20, y: 20, }),
    Some(small),
  )
  assert_eq(@selection.hit_target([big], { x: 101, y: 0, }), None)
}
