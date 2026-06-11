// Regression test for the streaming freeze: cmark can panic on some
// streaming-truncated inputs (observed: "Index out of bounds" in
// Parser::add_open_blocks while this answer streamed in). markdown_nodes
// must contain the panic and fall back to plain text, because view re-parses
// the accumulated text on every delta — one escaping panic freezes the
// transcript permanently.

///|
test "markdown survives every streaming prefix of a list-heavy answer" {
  let answer = "你好！😊 我是 OpenSeek，一个专注于 MoonBit 语言的 AI 编程助手。\n\n我可以帮你：\n\n- 🛠️ **写 MoonBit 代码**：函数、模块、测试\n- 🔍 **解释代码**：阅读和理解现有项目\n- 🐛 **修 bug**：定位并修复问题\n\n1. 第一步\n2. 第二步\n\n| 列 | 表 |\n|---|---|\n| a | b |\n"
  let chars = answer.iter().collect()
  let buf = StringBuilder::new()
  for ch in chars {
    buf.write_char(ch)
    let nodes = markdown_nodes(buf.to_string())
    assert_true(nodes.length() > 0)
  }
}

///|
test "a bare list marker at end of input renders via the fallback" {
  // Minimal reproducers for the cmark panic: a list marker as the very last
  // character of the document, with nothing (not even a newline) after it.
  for text in ["-", "*", "+", "1.", "1)", "\n-", "- a\n-", "你可以：\n\n-"] {
    let nodes = markdown_nodes(text)
    assert_true(nodes.length() > 0)
  }
}
