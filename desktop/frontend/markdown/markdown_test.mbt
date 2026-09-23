///|
test "markdown survives every streaming prefix of a list-heavy answer" {
  let answer = "你好！😊 我是 SeekMoon，一个专注于 MoonBit 语言的 AI 编程助手。\n\n我可以帮你：\n\n- 🛠️ **写 MoonBit 代码**：函数、模块、测试\n- 🔍 **解释代码**：阅读和理解现有项目\n- 🐛 **修 bug**：定位并修复问题\n\n1. 第一步\n2. 第二步\n\n| 列 | 表 |\n|---|---|\n| a | b |\n"
  let buf = StringBuilder()
  for ch in answer {
    buf.write_char(ch)
    let nodes = @markdown.markdown_nodes(buf.to_string())
    assert_true(nodes.length() > 0)
  }
}

///|
test "a bare list marker at end of input renders via the fallback" {
  // Minimal reproducers for the cmark panic: a list marker as the very last
  // character of the document, with nothing (not even a newline) after it.
  for text in ["-", "*", "+", "1.", "1)", "\n-", "- a\n-", "你可以：\n\n-"] {
    let nodes = @markdown.markdown_nodes(text)
    assert_true(nodes.length() > 0)
  }
}

///|
test "markdown file actions decode URI destinations exactly once" {
  let paths : Array[String] = []
  let open = path => {
    paths.push(path)
    @cmd.none
  }
  let root = "/Users/me/Library/Application"
  ignore(
    @markdown.markdown_nodes(
      "[guide](\{root}%20Support/SeekMoon/gmachine-3.md)",
      open_file=open,
    ),
  )
  ignore(
    @markdown.markdown_nodes(
      "[guide][doc]\n\n[doc]: ./docs/%E4%B8%AD%E6%96%87%20guide.md#L12",
      open_file=open,
    ),
  )
  ignore(
    @markdown.markdown_nodes(
      "[percent](./docs/100%25.md) [literal](./docs/a%2520b.md:12:3) [plus](./docs/a+b.md) [malformed](./docs/100%zz.md)",
      open_file=open,
    ),
  )
  ignore(
    @markdown.markdown_nodes(
      "[file](file:///tmp/Application%20Support/guide.md) `./docs/a%20b.md:12`",
      open_file=open,
    ),
  )
  assert_eq(paths, [
    "\{root} Support/SeekMoon/gmachine-3.md",
    "./docs/中文 guide.md#L12",
    "./docs/100%.md",
    "./docs/a%20b.md:12:3",
    "./docs/a+b.md",
    "./docs/100%zz.md",
    "/tmp/Application Support/guide.md",
  ])
}

///|
test "markdown renders block structure" {
  inspect(@markdown.markdown_nodes("").length(), content="0")
  inspect(@markdown.markdown_nodes("just a paragraph").length(), content="1")
  inspect(
    @markdown.markdown_nodes("# Title\n\nbody text").length(),
    content="2",
  )
  inspect(
    @markdown.markdown_nodes("- one\n- two\n- three").length(),
    content="1",
  )
  inspect(
    @markdown.markdown_nodes("para\n\n```moonbit\nfn main {}\n```\n\n---").length(),
    content="3",
  )
  inspect(@markdown.markdown_nodes("> quoted\n> text").length(), content="1")
  inspect(
    @markdown.markdown_nodes("| a | b |\n| - | - |\n| 1 | 2 |").length(),
    content="1",
  )
}

///|
test "markdown survives streaming-truncated input" {
  // An unterminated fence parses as *something* renderable rather than
  // aborting — the streaming view re-parses partial text on every delta.
  inspect(
    @markdown.markdown_nodes("intro\n\n```moonbit\nfn ma").length(),
    content="2",
  )
  inspect(@markdown.markdown_nodes("broken **emphasi").length(), content="1")
  inspect(@markdown.markdown_nodes("dangling [link](htt").length(), content="1")
}

///|
test "moonbit-family fences keep their block shape" {
  // The fence languages that route through the shared MoonBit tokenizer
  // (`moonbit` itself, plus the editor markdown pipeline's `mbt`/`mbtx`
  // aliases) each still render as exactly one block, exactly like a plain
  // fence — the tokenization changes the code payload, never the layout.
  for fence in ["moonbit", "mbt", "mbtx"] {
    inspect(
      @markdown.markdown_nodes(
        "intro\n\n```\{fence}\nlet answer = 42\n```\n\noutro",
      ).length(),
      content="3",
    )
  }
  inspect(
    @markdown.markdown_nodes("intro\n\n```\nplain text\n```\n\noutro").length(),
    content="3",
  )
}

///|
test "raw html stays text instead of markup" {
  // One pre.raw-html block; the structure proves the branch is taken and the
  // payload is routed through a text node, never through innerHTML.
  inspect(
    @markdown.markdown_nodes("<script>alert(1)</script>").length(),
    content="1",
  )
}

///|
test "a scheme without an authority remains text" {
  inspect(
    @markdown.linkified_text_nodes("streaming https://").length(),
    content="1",
  )
}
