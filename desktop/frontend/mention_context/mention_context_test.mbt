///|
test "encode without chips passes the task through untouched" {
  assert_eq(@mention_context.encode([], "plain prompt"), "plain prompt")
  assert_eq(@mention_context.encode([], "  padded  "), "padded")
}

///|
test "encode lays out the task first, then the tagged mention block" {
  let content = @mention_context.encode(
    [
      Skill(name="review-pr"),
      Symbol(name="parse_hover", file="src/hover.mbt", line=5),
      Symbol(name="unplaced", file="", line=0),
      Annotation(
        file="src/hover.mbt",
        start_line=12,
        end_line=13,
        quote="fn parse_hover() {\n  ...\n}",
        comment="this looks wrong",
      ),
    ],
    "look at this",
  )
  inspect(
    content,
    content=(
      #|look at this
      #|
      #|<user_mentions>
      #|<skill name="review-pr"/>
      #|<symbol name="parse_hover" file="src/hover.mbt" line="5"/>
      #|<symbol name="unplaced"/>
      #|<annotation file="src/hover.mbt" lines="12-13">
      #|<quote>
      #|fn parse_hover() {
      #|  ...
      #|}
      #|</quote>
      #|<user_comment>
      #|this looks wrong
      #|</user_comment>
      #|</annotation>
      #|</user_mentions>
    ),
  )
}

///|
test "encode of chips alone omits the task block" {
  inspect(
    @mention_context.encode([Skill(name="review-pr")], "  "),
    content=(
      #|<user_mentions>
      #|<skill name="review-pr"/>
      #|</user_mentions>
    ),
  )
}

///|
test "parse round-trips what encode wrote" {
  let mentions : Array[@mention_context.MentionRef] = [
    Skill(name="review-pr"),
    Symbol(name="parse_hover", file="src/hover.mbt", line=5),
    Symbol(name="unplaced", file="", line=0),
    Annotation(
      file="src/hover.mbt",
      start_line=12,
      end_line=13,
      quote="fn parse_hover() {\n  ...\n}",
      comment="this looks wrong",
    ),
  ]
  let task = "look at this\nand this"
  guard @mention_context.parse(@mention_context.encode(mentions, task))
    is Some(parsed) else {
    fail("round trip failed")
  }
  assert_eq(parsed.task, task)
  @debug.assert_eq(parsed.mentions, mentions)
}

///|
test "parse round-trips an annotation with empty bodies" {
  let mentions : Array[@mention_context.MentionRef] = [
    Annotation(file="a.mbt", start_line=3, end_line=3, quote="", comment=""),
  ]
  guard @mention_context.parse(@mention_context.encode(mentions, ""))
    is Some(parsed) else {
    fail("round trip failed")
  }
  @debug.assert_eq(parsed.mentions, mentions)
}

///|
test "parse tolerates a trailing newline and CRLF line ends" {
  let content = "task\r\n\r\n<user_mentions>\r\n<skill name=\"review-pr\"/>\r\n</user_mentions>\r\n"
  guard @mention_context.parse(content) is Some(parsed) else {
    fail("expected envelope")
  }
  assert_eq(parsed.task, "task")
  @debug.assert_eq(parsed.mentions, [Skill(name="review-pr")])
}

///|
test "parse accepts a symbol carrying a body of truncated source" {
  let content =
    #|<user_mentions>
    #|<symbol name="parse_hover" file="src/hover.mbt" line="5">
    #|fn parse_hover() {
    #|  ...
    #|</symbol>
    #|</user_mentions>
  guard @mention_context.parse(content) is Some(parsed) else {
    fail("expected envelope")
  }
  // The body was context for the model; the chip renders from the attributes.
  @debug.assert_eq(parsed.mentions, [
    Symbol(name="parse_hover", file="src/hover.mbt", line=5),
  ])
}

///|
test "parse rejects everything that is not a well-formed envelope" {
  // An ordinary message.
  assert_true(@mention_context.parse("just a prompt") is None)
  // Tags mentioned mid-text, not as the trailing block.
  assert_true(
    @mention_context.parse("the </user_mentions> tag closes it") is None,
  )
  // A closing tag with no opener.
  assert_true(@mention_context.parse("task\n</user_mentions>") is None)
  // An empty mention block.
  assert_true(
    @mention_context.parse("<user_mentions>\n</user_mentions>") is None,
  )
  // A line that is not a mention element.
  assert_true(
    @mention_context.parse("<user_mentions>\nnot a mention\n</user_mentions>")
    is None,
  )
  // A skill with no name.
  assert_true(
    @mention_context.parse(
      "<user_mentions>\n<skill name=\"\"/>\n</user_mentions>",
    )
    is None,
  )
  // A symbol with a body but no closing tag.
  assert_true(
    @mention_context.parse(
      "<user_mentions>\n<symbol name=\"x\">\nbody\n</user_mentions>",
    )
    is None,
  )
  // An annotation missing its comment block.
  assert_true(
    @mention_context.parse(
      (
        #|<user_mentions>
        #|<annotation file="a.mbt" lines="1-2">
        #|<quote>
        #|q
        #|</quote>
        #|</annotation>
        #|</user_mentions>
      ),
    )
    is None,
  )
}

///|
test "parse takes the last opener when the task text spells one" {
  let content = @mention_context.encode(
    [Skill(name="review-pr")],
    "quoting the marker:\n<user_mentions>",
  )
  guard @mention_context.parse(content) is Some(parsed) else {
    fail("expected envelope")
  }
  // The quoted opener stays in the task; only the real block parses as chips.
  assert_eq(parsed.task, "quoting the marker:\n<user_mentions>")
  @debug.assert_eq(parsed.mentions, [Skill(name="review-pr")])
}
