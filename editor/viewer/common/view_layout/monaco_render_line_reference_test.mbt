// Conformance port of Monaco/VS Code view-line rendering suites.
//
// Ports:
//   vscode/src/vs/editor/common/viewLayout/lineDecorations.test.ts (5 cases)
//   vscode/src/vs/editor/common/viewLayout/viewLineRenderer.test.ts (72 cases)
// From the checked-in vscode submodule.
//
// `viewer/view_line_renderer` is a faithful 1:1 port of Monaco's
// `viewLineRenderer.ts`, so every case asserts Monaco's exact output: the inner
// HTML matches the `__snapshots__/*.0.html` byte-for-byte and the inflated
// `CharacterMapping` matches `__snapshots__/*.1.snap`. `inner()` strips this
// package's only deviation — the `<span class="view-line-content">` line
// wrapper (Monaco uses a bare `<span>`; the browser layer needs the class for
// `querySelector`/CSS) — so the comparison is against Monaco's inflated output.
//
// Cases that Monaco asserts with `assert.strictEqual` instead of `assertSnapshot`
// (character replacement, parts, large-token splitting, getColumn) embed the
// expected values from the `.ts` source directly.

///|
test "monaco lineDecorations normalizer reference suite" {
  let content = "abcabcabcabcabcabcabcabcabcabc"
  assert_segments(
    "Bug 9827",
    @view_layout.LineDecorationsNormalizer::normalize(content, [
      LineDecoration(1, 11, "c1"),
      LineDecoration(3, 4, "c2"),
    ]),
    [segment(0, 1, "c1"), segment(2, 2, "c2 c1"), segment(3, 9, "c1")],
  )
  assert_segments(
    "issue #3462",
    @view_layout.LineDecorationsNormalizer::normalize(content, [
      LineDecoration(15, 21, "mtkw"),
      LineDecoration(20, 21, "inline-folded"),
    ]),
    [segment(14, 18, "mtkw"), segment(19, 19, "mtkw inline-folded")],
  )
  assert_segments(
    "ViewLineParts separate decorations",
    @view_layout.LineDecorationsNormalizer::normalize(content, [
      LineDecoration(1, 2, "c1"),
      LineDecoration(3, 4, "c2"),
    ]),
    [segment(0, 0, "c1"), segment(2, 2, "c2")],
  )
  assert_segments(
    "ViewLineParts adjacent decorations",
    @view_layout.LineDecorationsNormalizer::normalize(content, [
      LineDecoration(1, 3, "c1"),
      LineDecoration(3, 4, "c2"),
    ]),
    [segment(0, 1, "c1"), segment(2, 2, "c2")],
  )
  assert_segments(
    "ViewLineParts overlapping decorations",
    @view_layout.LineDecorationsNormalizer::normalize(content, [
      LineDecoration(1, 4, "c1"),
      LineDecoration(3, 4, "c2"),
    ]),
    [segment(0, 1, "c1"), segment(2, 2, "c1 c2")],
  )
  assert_segments(
    "ViewLineParts duplicated base decorations",
    @view_layout.LineDecorationsNormalizer::normalize(content, [
      LineDecoration(1, 4, "c1"),
      LineDecoration(1, 4, "c1*"),
      LineDecoration(3, 4, "c2"),
    ]),
    [segment(0, 1, "c1 c1*"), segment(2, 2, "c1 c1* c2")],
  )
  assert_segments(
    "ViewLineParts three duplicated base decorations",
    @view_layout.LineDecorationsNormalizer::normalize(content, [
      LineDecoration(1, 4, "c1"),
      LineDecoration(1, 4, "c1*"),
      LineDecoration(1, 4, "c1**"),
      LineDecoration(3, 4, "c2"),
    ]),
    [segment(0, 1, "c1 c1* c1**"), segment(2, 2, "c1 c1* c1** c2")],
  )
  assert_segments(
    "ViewLineParts duplicated overlap decorations",
    @view_layout.LineDecorationsNormalizer::normalize(content, [
      LineDecoration(1, 4, "c1"),
      LineDecoration(1, 4, "c1*"),
      LineDecoration(1, 4, "c1**"),
      LineDecoration(3, 4, "c2"),
      LineDecoration(3, 4, "c2*"),
    ]),
    [segment(0, 1, "c1 c1* c1**"), segment(2, 2, "c1 c1* c1** c2 c2*")],
  )
  assert_segments(
    "ViewLineParts overlap with longer tail",
    @view_layout.LineDecorationsNormalizer::normalize(content, [
      LineDecoration(1, 4, "c1"),
      LineDecoration(1, 4, "c1*"),
      LineDecoration(1, 4, "c1**"),
      LineDecoration(3, 4, "c2"),
      LineDecoration(3, 5, "c2*"),
    ]),
    [
      segment(0, 1, "c1 c1* c1**"),
      segment(2, 2, "c1 c1* c1** c2 c2*"),
      segment(3, 3, "c2*"),
    ],
  )
}

///|
test "monaco lineDecoration compare order is preserved in render input" {
  let input = monaco_input("x", [p(1, 1)], line_decorations=[
    LineDecoration(1, 1, "regular", decoration_type=Regular),
    LineDecoration(1, 1, "before", decoration_type=Before),
    LineDecoration(1, 1, "after", decoration_type=After),
    LineDecoration(
      1,
      1,
      "regular-affecting",
      decoration_type=RegularAffectingLetterSpacing,
    ),
  ])
  assert_eq(input.line_decorations[0].class_name, "before")
  assert_eq(input.line_decorations[1].class_name, "after")
  assert_eq(input.line_decorations[2].class_name, "regular")
  assert_eq(input.line_decorations[3].class_name, "regular-affecting")
}

///|
test "replaces spaces" {
  let o0 = mr(" ", [p(1, 0)], tab_size=4)
  assert_html(
    o0,
    (
      #|<span class="mtk0"> </span>
    ),
  )
  assert_map(
    o0,
    (
      #|[[0,0,0][0,1,1]]
    ),
  )
  let o1 = mr("  ", [p(2, 0)], tab_size=4)
  assert_html(
    o1,
    (
      #|<span class="mtk0">  </span>
    ),
  )
  assert_map(
    o1,
    (
      #|[[0,0,0][0,1,1][0,2,2]]
    ),
  )
  let o2 = mr("a  b", [p(4, 0)], tab_size=4)
  assert_html(
    o2,
    (
      #|<span class="mtk0">a  b</span>
    ),
  )
  assert_map(
    o2,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4]]
    ),
  )
}

///|
test "escapes HTML markup" {
  let o0 = mr("a<b", [p(3, 0)], tab_size=4)
  assert_html(
    o0,
    (
      #|<span class="mtk0">a&lt;b</span>
    ),
  )
  assert_map(
    o0,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3]]
    ),
  )
  let o1 = mr("a>b", [p(3, 0)], tab_size=4)
  assert_html(
    o1,
    (
      #|<span class="mtk0">a&gt;b</span>
    ),
  )
  assert_map(
    o1,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3]]
    ),
  )
  let o2 = mr("a&b", [p(3, 0)], tab_size=4)
  assert_html(
    o2,
    (
      #|<span class="mtk0">a&amp;b</span>
    ),
  )
  assert_map(
    o2,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3]]
    ),
  )
}

///|
test "replaces some bad characters" {
  let o0 = mr("a\u{0000}b", [p(3, 0)], tab_size=4)
  assert_html(
    o0,
    (
      #|<span class="mtk0">a&#00;b</span>
    ),
  )
  assert_map(
    o0,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3]]
    ),
  )
  let o1 = mr("a\u{FEFF}b", [p(3, 0)], tab_size=4)
  assert_html(
    o1,
    (
      #|<span class="mtk0">a�b</span>
    ),
  )
  assert_map(
    o1,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3]]
    ),
  )
  let o2 = mr("a\u{2028}b", [p(3, 0)], tab_size=4)
  assert_html(
    o2,
    (
      #|<span class="mtk0">a�b</span>
    ),
  )
  assert_map(
    o2,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3]]
    ),
  )
}

///|
test "handles tabs" {
  let o0 = mr("\t", [p(1, 0)], tab_size=4)
  assert_html(
    o0,
    (
      #|<span class="mtk0">    </span>
    ),
  )
  assert_map(
    o0,
    (
      #|[[0,0,0][0,4,4]]
    ),
  )
  let o1 = mr("x\t", [p(2, 0)], tab_size=4)
  assert_html(
    o1,
    (
      #|<span class="mtk0">x   </span>
    ),
  )
  assert_map(
    o1,
    (
      #|[[0,0,0][0,1,1][0,4,4]]
    ),
  )
  let o2 = mr("xx\t", [p(3, 0)], tab_size=4)
  assert_html(
    o2,
    (
      #|<span class="mtk0">xx  </span>
    ),
  )
  assert_map(
    o2,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,4,4]]
    ),
  )
  let o3 = mr("xxx\t", [p(4, 0)], tab_size=4)
  assert_html(
    o3,
    (
      #|<span class="mtk0">xxx </span>
    ),
  )
  assert_map(
    o3,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4]]
    ),
  )
  let o4 = mr("xxxx\t", [p(5, 0)], tab_size=4)
  assert_html(
    o4,
    (
      #|<span class="mtk0">xxxx    </span>
    ),
  )
  assert_map(
    o4,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,8,8]]
    ),
  )
}

///|
test "empty line" {
  let out = mr("", [])
  assert_html(
    out,
    (
      #|<span></span>
    ),
  )
  assert_map(
    out,
    (
      #|[]
    ),
  )
}

///|
test "uses part type" {
  let o0 = mr("x", [p(1, 10)])
  assert_html(
    o0,
    (
      #|<span class="mtk10">x</span>
    ),
  )
  assert_map(
    o0,
    (
      #|[[0,0,0][0,1,1]]
    ),
  )
  let o1 = mr("x", [p(1, 20)])
  assert_html(
    o1,
    (
      #|<span class="mtk20">x</span>
    ),
  )
  assert_map(
    o1,
    (
      #|[[0,0,0][0,1,1]]
    ),
  )
  let o2 = mr("x", [p(1, 30)])
  assert_html(
    o2,
    (
      #|<span class="mtk30">x</span>
    ),
  )
  assert_map(
    o2,
    (
      #|[[0,0,0][0,1,1]]
    ),
  )
}

///|
test "two parts" {
  let o0 = mr("xy", [p(1, 1), p(2, 2)])
  assert_html(
    o0,
    (
      #|<span class="mtk1">x</span><span class="mtk2">y</span>
    ),
  )
  assert_map(
    o0,
    (
      #|[[0,0,0][1,0,1][1,1,2]]
    ),
  )
  let o1 = mr("xyz", [p(1, 1), p(3, 2)])
  assert_html(
    o1,
    (
      #|<span class="mtk1">x</span><span class="mtk2">yz</span>
    ),
  )
  assert_map(
    o1,
    (
      #|[[0,0,0][1,0,1][1,1,2][1,2,3]]
    ),
  )
  let o2 = mr("xyz", [p(2, 1), p(3, 2)])
  assert_html(
    o2,
    (
      #|<span class="mtk1">xy</span><span class="mtk2">z</span>
    ),
  )
  assert_map(
    o2,
    (
      #|[[0,0,0][0,1,1][1,0,2][1,1,3]]
    ),
  )
}

///|
test "overflow" {
  let out = mr(
    "Hello world!",
    [
      p(1, 0),
      p(2, 1),
      p(3, 2),
      p(4, 3),
      p(5, 4),
      p(6, 5),
      p(7, 6),
      p(8, 7),
      p(9, 8),
      p(10, 9),
      p(11, 10),
      p(12, 11),
    ],
    stop_rendering_line_after=6,
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="mtk0">H</span><span class="mtk1">e</span><span class="mtk2">l</span><span class="mtk3">l</span><span class="mtk4">o</span><span class="mtk5"> </span><span class="mtkoverflow">Show more (6 chars)</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][2,0,2][3,0,3][4,0,4][5,0,5][5,1,6]]
    ),
  )
}

///|
test "typical" {
  let out = mr(
    "\t    export class Game { // http://test.com     ",
    [
      p(5, 1),
      p(11, 2),
      p(12, 3),
      p(17, 4),
      p(18, 5),
      p(22, 6),
      p(23, 7),
      p(24, 8),
      p(25, 9),
      p(28, 10),
      p(43, 11),
      p(48, 12),
    ],
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:40px">→   </span><span class="mtkz" style="width:40px">·‌·‌·‌·‌</span><span class="mtk2">export</span><span class="mtk3"> </span><span class="mtk4">class</span><span class="mtk5"> </span><span class="mtk6">Game</span><span class="mtk7"> </span><span class="mtk8">{</span><span class="mtk9"> </span><span class="mtk10">// </span><span class="mtk11">http://test.com</span><span class="mtkz" style="width:20px">·‌·‌</span><span class="mtkz" style="width:30px">·‌·‌·‌</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,4][1,2,5][1,4,6][1,6,7][2,0,8][2,1,9][2,2,10][2,3,11][2,4,12][2,5,13][3,0,14][4,0,15][4,1,16][4,2,17][4,3,18][4,4,19][5,0,20][6,0,21][6,1,22][6,2,23][6,3,24][7,0,25][8,0,26][9,0,27][10,0,28][10,1,29][10,2,30][11,0,31][11,1,32][11,2,33][11,3,34][11,4,35][11,5,36][11,6,37][11,7,38][11,8,39][11,9,40][11,10,41][11,11,42][11,12,43][11,13,44][11,14,45][12,0,46][12,2,47][13,0,48][13,2,49][13,4,50][13,6,51]]
    ),
  )
}

///|
test "issue-2255-1" {
  let out = mr(
    "\t\t\tcursorStyle:\t\t\t\t\t\t(prevOpts.cursorStyle !== newOpts.cursorStyle),",
    [
      p(3, 1),
      p(15, 2),
      p(21, 3),
      p(22, 4),
      p(43, 5),
      p(45, 6),
      p(46, 7),
      p(66, 8),
      p(67, 9),
      p(68, 10),
    ],
  )
  assert_html(
    out,
    (
      #|<span class="mtk1">            </span><span class="mtk2">cursorStyle:</span><span class="mtk3">                        </span><span class="mtk4">(</span><span class="mtk5">prevOpts.cursorStyle </span><span class="mtk6">!=</span><span class="mtk7">=</span><span class="mtk8"> newOpts.cursorStyle</span><span class="mtk9">)</span><span class="mtk10">,</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,4,4][0,8,8][1,0,12][1,1,13][1,2,14][1,3,15][1,4,16][1,5,17][1,6,18][1,7,19][1,8,20][1,9,21][1,10,22][1,11,23][2,0,24][2,4,28][2,8,32][2,12,36][2,16,40][2,20,44][3,0,48][4,0,49][4,1,50][4,2,51][4,3,52][4,4,53][4,5,54][4,6,55][4,7,56][4,8,57][4,9,58][4,10,59][4,11,60][4,12,61][4,13,62][4,14,63][4,15,64][4,16,65][4,17,66][4,18,67][4,19,68][4,20,69][5,0,70][5,1,71][6,0,72][7,0,73][7,1,74][7,2,75][7,3,76][7,4,77][7,5,78][7,6,79][7,7,80][7,8,81][7,9,82][7,10,83][7,11,84][7,12,85][7,13,86][7,14,87][7,15,88][7,16,89][7,17,90][7,18,91][7,19,92][8,0,93][9,0,94][9,1,95]]
    ),
  )
}

///|
test "issue-2255-2" {
  let out = mr(
    " \t\t\tcursorStyle:\t\t\t\t\t\t(prevOpts.cursorStyle !== newOpts.cursorStyle),",
    [
      p(4, 1),
      p(16, 2),
      p(22, 3),
      p(23, 4),
      p(44, 5),
      p(46, 6),
      p(47, 7),
      p(67, 8),
      p(68, 9),
      p(69, 10),
    ],
  )
  assert_html(
    out,
    (
      #|<span class="mtk1">            </span><span class="mtk2">cursorStyle:</span><span class="mtk3">                        </span><span class="mtk4">(</span><span class="mtk5">prevOpts.cursorStyle </span><span class="mtk6">!=</span><span class="mtk7">=</span><span class="mtk8"> newOpts.cursorStyle</span><span class="mtk9">)</span><span class="mtk10">,</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,4,4][0,8,8][1,0,12][1,1,13][1,2,14][1,3,15][1,4,16][1,5,17][1,6,18][1,7,19][1,8,20][1,9,21][1,10,22][1,11,23][2,0,24][2,4,28][2,8,32][2,12,36][2,16,40][2,20,44][3,0,48][4,0,49][4,1,50][4,2,51][4,3,52][4,4,53][4,5,54][4,6,55][4,7,56][4,8,57][4,9,58][4,10,59][4,11,60][4,12,61][4,13,62][4,14,63][4,15,64][4,16,65][4,17,66][4,18,67][4,19,68][4,20,69][5,0,70][5,1,71][6,0,72][7,0,73][7,1,74][7,2,75][7,3,76][7,4,77][7,5,78][7,6,79][7,7,80][7,8,81][7,9,82][7,10,83][7,11,84][7,12,85][7,13,86][7,14,87][7,15,88][7,16,89][7,17,90][7,18,91][7,19,92][8,0,93][9,0,94][9,1,95]]
    ),
  )
}

///|
test "issue-91178" {
  let out = mr(
    "//just a comment",
    [p(16, 1)],
    line_decorations=[dec(13, 13, "dec1", After), dec(13, 13, "dec2", Before)],
    use_monospace_optimizations=true,
    can_use_halfwidth_rightwards_arrow=false,
  )
  assert_html(
    out,
    (
      #|<span class="mtk1">//just a com</span><span class="mtk1 dec2"></span><span class="mtk1 dec1"></span><span class="mtk1">ment</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][2,0,12][3,1,13][3,2,14][3,3,15][3,4,16]]
    ),
  )
}

///|
test "monaco-280" {
  let out = mr(
    "var קודמות = \"מיותר קודמות צ'ט של, אם לשון העברית שינויים ויש, אם\";",
    [p(3, 6), p(13, 1), p(66, 20), p(67, 1)],
    contains_rtl=true,
    is_basic_ascii=false,
  )
  assert_html(
    out,
    (
      #|<span class="mtk6">var</span><span style="unicode-bidi:isolate" class="mtk1"> קודמות = </span><span style="unicode-bidi:isolate" class="mtk20">"מיותר קודמות צ'ט של, אם לשון העברית שינויים ויש, אם"</span><span class="mtk1">;</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][1,0,3][1,1,4][1,2,5][1,3,6][1,4,7][1,5,8][1,6,9][1,7,10][1,8,11][1,9,12][2,0,13][2,1,14][2,2,15][2,3,16][2,4,17][2,5,18][2,6,19][2,7,20][2,8,21][2,9,22][2,10,23][2,11,24][2,12,25][2,13,26][2,14,27][2,15,28][2,16,29][2,17,30][2,18,31][2,19,32][2,20,33][2,21,34][2,22,35][2,23,36][2,24,37][2,25,38][2,26,39][2,27,40][2,28,41][2,29,42][2,30,43][2,31,44][2,32,45][2,33,46][2,34,47][2,35,48][2,36,49][2,37,50][2,38,51][2,39,52][2,40,53][2,41,54][2,42,55][2,43,56][2,44,57][2,45,58][2,46,59][2,47,60][2,48,61][2,49,62][2,50,63][2,51,64][2,52,65][3,0,66][3,1,67]]
    ),
  )
}

///|
test "issue-137036" {
  let out = mr(
    "<option value=\"العربية\">العربية</option>",
    [
      p(1, 2),
      p(7, 3),
      p(8, 4),
      p(13, 5),
      p(14, 4),
      p(23, 6),
      p(24, 2),
      p(31, 4),
      p(33, 2),
      p(39, 3),
      p(40, 2),
    ],
    contains_rtl=true,
    is_basic_ascii=false,
  )
  assert_html(
    out,
    (
      #|<span class="mtk2">&lt;</span><span class="mtk3">option</span><span class="mtk4"> </span><span class="mtk5">value</span><span class="mtk4">=</span><span style="unicode-bidi:isolate" class="mtk6">"العربية"</span><span class="mtk2">&gt;</span><span style="unicode-bidi:isolate" class="mtk4">العربية</span><span class="mtk2">&lt;/</span><span class="mtk3">option</span><span class="mtk2">&gt;</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][1,1,2][1,2,3][1,3,4][1,4,5][1,5,6][2,0,7][3,0,8][3,1,9][3,2,10][3,3,11][3,4,12][4,0,13][5,0,14][5,1,15][5,2,16][5,3,17][5,4,18][5,5,19][5,6,20][5,7,21][5,8,22][6,0,23][7,0,24][7,1,25][7,2,26][7,3,27][7,4,28][7,5,29][7,6,30][8,0,31][8,1,32][9,0,33][9,1,34][9,2,35][9,3,36][9,4,37][9,5,38][10,0,39][10,1,40]]
    ),
  )
}

///|
test "issue-99589" {
  let out = mr(
    "    [\"🖨️ چاپ فاکتور\",\"🎨 تنظیمات\"]",
    [p(5, 2), p(21, 3), p(22, 2), p(34, 3), p(35, 2)],
    contains_rtl=true,
    is_basic_ascii=false,
    use_monospace_optimizations=true,
    render_whitespace=All,
  )
  assert_html(
    out,
    (
      #|<span class="mtkw">·‌·‌·‌·‌</span><span class="mtk2">[</span><span style="unicode-bidi:isolate" class="mtk3">"🖨️ چاپ فاکتور"</span><span class="mtk2">,</span><span style="unicode-bidi:isolate" class="mtk3">"🎨 تنظیمات"</span><span class="mtk2">]</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,2,1][0,4,2][0,6,3][1,0,4][2,0,5][2,1,6][2,2,7][2,3,8][2,4,9][2,5,10][2,6,11][2,7,12][2,8,13][2,9,14][2,10,15][2,11,16][2,12,17][2,13,18][2,14,19][2,15,20][3,0,21][4,0,22][4,1,23][4,2,24][4,3,25][4,4,26][4,5,27][4,6,28][4,7,29][4,8,30][4,9,31][4,10,32][4,11,33][5,0,34][5,1,35]]
    ),
  )
}

///|
test "issue-260239" {
  let out = mr(
    "<p class=\"myclass\" title=\"العربي\">نشاط التدويل!</p>",
    [
      p(1, 1),
      p(2, 2),
      p(3, 3),
      p(8, 4),
      p(9, 5),
      p(10, 6),
      p(17, 7),
      p(18, 6),
      p(19, 3),
      p(24, 4),
      p(25, 5),
      p(26, 6),
      p(32, 8),
      p(33, 6),
      p(34, 1),
      p(47, 9),
      p(48, 1),
      p(49, 2),
      p(50, 2),
      p(51, 1),
    ],
    contains_rtl=true,
    is_basic_ascii=false,
  )
  assert_html(
    out,
    (
      #|<span class="mtk1">&lt;</span><span class="mtk2">p</span><span class="mtk3"> </span><span class="mtk4">class</span><span class="mtk5">=</span><span class="mtk6">"</span><span class="mtk7">myclass</span><span class="mtk6">"</span><span class="mtk3"> </span><span class="mtk4">title</span><span class="mtk5">=</span><span class="mtk6">"</span><span style="unicode-bidi:isolate" class="mtk8">العربي</span><span class="mtk6">"</span><span class="mtk1">&gt;</span><span style="unicode-bidi:isolate" class="mtk9">نشاط التدويل!</span><span class="mtk1">&lt;</span><span class="mtk2">/</span><span class="mtk2">p</span><span class="mtk1">&gt;</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][2,0,2][3,0,3][3,1,4][3,2,5][3,3,6][3,4,7][4,0,8][5,0,9][6,0,10][6,1,11][6,2,12][6,3,13][6,4,14][6,5,15][6,6,16][7,0,17][8,0,18][9,0,19][9,1,20][9,2,21][9,3,22][9,4,23][10,0,24][11,0,25][12,0,26][12,1,27][12,2,28][12,3,29][12,4,30][12,5,31][13,0,32][14,0,33][15,0,34][15,1,35][15,2,36][15,3,37][15,4,38][15,5,39][15,6,40][15,7,41][15,8,42][15,9,43][15,10,44][15,11,45][15,12,46][16,0,47][17,0,48][18,0,49][19,0,50][19,1,51]]
    ),
  )
}

///|
test "issue-274604" {
  let out = mr(
    "test.com##a:-abp-contains(إ)",
    [p("test.com##a:-abp-contains(إ)".length(), 1)],
    contains_rtl=true,
    is_basic_ascii=false,
  )
  assert_html(
    out,
    (
      #|<span style="unicode-bidi:isolate" class="mtk1">test.com##a:-abp-contains(إ)</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][0,21,21][0,22,22][0,23,23][0,24,24][0,25,25][0,26,26][0,27,27][0,28,28]]
    ),
  )
}

///|
test "issue-277693" {
  let out = mr(
    "نام کاربر: ${user.firstName}",
    [p(9, 1), p(11, 1), p(13, 2), p(17, 3), p(18, 4), p(27, 3), p(28, 2)],
    contains_rtl=true,
    is_basic_ascii=false,
  )
  assert_html(
    out,
    (
      #|<span style="unicode-bidi:isolate" class="mtk1">نام کاربر</span><span class="mtk1">: </span><span class="mtk2">${</span><span class="mtk3">user</span><span class="mtk4">.</span><span class="mtk3">firstName</span><span class="mtk2">}</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][1,0,9][1,1,10][2,0,11][2,1,12][3,0,13][3,1,14][3,2,15][3,3,16][4,0,17][5,0,18][5,1,19][5,2,20][5,3,21][5,4,22][5,5,23][5,6,24][5,7,25][5,8,26][6,0,27][6,1,28]]
    ),
  )
}

///|
test "issue-6885-rtl" {
  let out = mr(
    "את גרמנית בהתייחסות שמו, שנתי המשפט אל חפש, אם כתב אחרים ולחבר. של התוכן אודות בויקיפדיה כלל, של עזרה כימיה היא. על עמוד יוצרים מיתולוגיה סדר, אם שכל שתפו לעברית שינויים, אם שאלות אנגלית עזה. שמות בקלות מה סדר.",
    [
      p(
        "את גרמנית בהתייחסות שמו, שנתי המשפט אל חפש, אם כתב אחרים ולחבר. של התוכן אודות בויקיפדיה כלל, של עזרה כימיה היא. על עמוד יוצרים מיתולוגיה סדר, אם שכל שתפו לעברית שינויים, אם שאלות אנגלית עזה. שמות בקלות מה סדר.".length(),
        1,
      ),
    ],
    contains_rtl=true,
    is_basic_ascii=false,
  )
  assert_html(
    out,
    (
      #|<span style="unicode-bidi:isolate" class="mtk1">את גרמנית בהתייחסות שמו, שנתי המשפט אל חפש, אם כתב אחרים ולחבר. של התוכן אודות בויקיפדיה כלל, של עזרה כימיה היא. על עמוד יוצרים מיתולוגיה סדר, אם שכל שתפו לעברית שינויים, אם שאלות אנגלית עזה. שמות בקלות מה סדר.</span>
    ),
  )
}

///|
test "issue-95685" {
  let out = mr(
    "var ftext = [\u{2029}\"Und\", \"dann\", \"eines\"];",
    [p("var ftext = [\u{2029}\"Und\", \"dann\", \"eines\"];".length(), 1)],
    is_basic_ascii=false,
  )
  assert_html(
    out,
    (
      #|<span class="mtk1">var ftext = [�"Und", "dann", "eines"];</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][0,21,21][0,22,22][0,23,23][0,24,24][0,25,25][0,26,26][0,27,27][0,28,28][0,29,29][0,30,30][0,31,31][0,32,32][0,33,33][0,34,34][0,35,35][0,36,36][0,37,37][0,38,38]]
    ),
  )
}

///|
test "issue-19673" {
  let out = mr(
    "    MongoCallback<string>): void {",
    [
      p(17, 1),
      p(18, 2),
      p(24, 3),
      p(26, 4),
      p(27, 5),
      p(28, 6),
      p(32, 7),
      p(34, 8),
    ],
    use_monospace_optimizations=true,
    faux_indent_length=4,
  )
  assert_html(
    out,
    (
      #|<span class="">    </span><span class="mtk1">MongoCallback</span><span class="mtk2">&lt;</span><span class="mtk3">string</span><span class="mtk4">&gt;)</span><span class="mtk5">:</span><span class="mtk6"> </span><span class="mtk7">void</span><span class="mtk8"> {</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][1,0,4][1,1,5][1,2,6][1,3,7][1,4,8][1,5,9][1,6,10][1,7,11][1,8,12][1,9,13][1,10,14][1,11,15][1,12,16][2,0,17][3,0,18][3,1,19][3,2,20][3,3,21][3,4,22][3,5,23][4,0,24][4,1,25][5,0,26][6,0,27][7,0,28][7,1,29][7,2,30][7,3,31][8,0,32][8,1,33][8,2,34]]
    ),
  )
}

///|
test "issue-18616" {
  let out = mr("https://microsoft.com", [p(21, 3)], line_decorations=[
    dec(1, 22, "link", Regular),
  ])
  assert_html(
    out,
    (
      #|<span class="mtk3 link">https://microsoft.com</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][0,21,21]]
    ),
  )
}

///|
test "issue-19207" {
  let out = mr(
    "'let url = `http://***/_api/web/lists/GetByTitle(\\'Teambuildingaanvragen\\')/items`;'",
    [p(49, 6), p(51, 4), p(72, 6), p(74, 4), p(84, 6)],
    line_decorations=[dec(13, 51, "detected-link", Regular)],
    use_monospace_optimizations=true,
  )
  assert_html(
    out,
    (
      #|<span class="mtk6">'let url = `</span><span class="mtk6 detected-link">http://***/_api/web/lists/GetByTitle(</span><span class="mtk4 detected-link">\</span><span class="mtk4">'</span><span class="mtk6">Teambuildingaanvragen</span><span class="mtk4">\'</span><span class="mtk6">)/items`;'</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][1,0,12][1,1,13][1,2,14][1,3,15][1,4,16][1,5,17][1,6,18][1,7,19][1,8,20][1,9,21][1,10,22][1,11,23][1,12,24][1,13,25][1,14,26][1,15,27][1,16,28][1,17,29][1,18,30][1,19,31][1,20,32][1,21,33][1,22,34][1,23,35][1,24,36][1,25,37][1,26,38][1,27,39][1,28,40][1,29,41][1,30,42][1,31,43][1,32,44][1,33,45][1,34,46][1,35,47][1,36,48][2,0,49][3,0,50][4,0,51][4,1,52][4,2,53][4,3,54][4,4,55][4,5,56][4,6,57][4,7,58][4,8,59][4,9,60][4,10,61][4,11,62][4,12,63][4,13,64][4,14,65][4,15,66][4,16,67][4,17,68][4,18,69][4,19,70][4,20,71][5,0,72][5,1,73][6,0,74][6,1,75][6,2,76][6,3,77][6,4,78][6,5,79][6,6,80][6,7,81][6,8,82][6,9,83][6,10,84]]
    ),
  )
}

///|
test "simple" {
  let out = mr("Hello world!", [p(12, 1)])
  assert_html(
    out,
    (
      #|<span class="mtk1">Hello world!</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12]]
    ),
  )
}

///|
test "two-tokens" {
  let out = mr("Hello world!", [p(6, 1), p(12, 2)])
  assert_html(
    out,
    (
      #|<span class="mtk1">Hello </span><span class="mtk2">world!</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][1,0,6][1,1,7][1,2,8][1,3,9][1,4,10][1,5,11][1,6,12]]
    ),
  )
}

///|
test "ws-4-leading" {
  let out = mr(
    "    Hello world!    ",
    [p(4, 1), p(6, 2), p(20, 3)],
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:40px">·‌·‌·‌·‌</span><span class="mtk2">He</span><span class="mtk3">llo world!</span><span class="mtkz" style="width:40px">·‌·‌·‌·‌</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,2,1][0,4,2][0,6,3][1,0,4][1,1,5][2,0,6][2,1,7][2,2,8][2,3,9][2,4,10][2,5,11][2,6,12][2,7,13][2,8,14][2,9,15][3,0,16][3,2,17][3,4,18][3,6,19][3,8,20]]
    ),
  )
}

///|
test "ws-8-leading" {
  let out = mr(
    "        Hello world!        ",
    [p(8, 1), p(10, 2), p(28, 3)],
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:40px">·‌·‌·‌·‌</span><span class="mtkz" style="width:40px">·‌·‌·‌·‌</span><span class="mtk2">He</span><span class="mtk3">llo world!</span><span class="mtkz" style="width:40px">·‌·‌·‌·‌</span><span class="mtkz" style="width:40px">·‌·‌·‌·‌</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,2,1][0,4,2][0,6,3][1,0,4][1,2,5][1,4,6][1,6,7][2,0,8][2,1,9][3,0,10][3,1,11][3,2,12][3,3,13][3,4,14][3,5,15][3,6,16][3,7,17][3,8,18][3,9,19][4,0,20][4,2,21][4,4,22][4,6,23][5,0,24][5,2,25][5,4,26][5,6,27][5,8,28]]
    ),
  )
}

///|
test "ws-2-tabs" {
  let out = mr(
    "\t\tHello world!\t",
    [p(2, 1), p(4, 2), p(15, 3)],
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:40px">→   </span><span class="mtkz" style="width:40px">→   </span><span class="mtk2">He</span><span class="mtk3">llo world!</span><span class="mtkz" style="width:40px">→   </span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,4][2,0,8][2,1,9][3,0,10][3,1,11][3,2,12][3,3,13][3,4,14][3,5,15][3,6,16][3,7,17][3,8,18][3,9,19][4,0,20][4,4,24]]
    ),
  )
}

///|
test "ws-mixed" {
  let out = mr(
    "  \t\t  Hello world! \t  \t   \t    ",
    [p(6, 1), p(8, 2), p(31, 3)],
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:40px">·‌·‌→ </span><span class="mtkz" style="width:40px">→   </span><span class="mtkz" style="width:20px">·‌·‌</span><span class="mtk2">He</span><span class="mtk3">llo world!</span><span class="mtkz" style="width:20px">·‌￫</span><span class="mtkz" style="width:40px">·‌·‌→ </span><span class="mtkz" style="width:40px">·‌·‌·‌￫</span><span class="mtkz" style="width:40px">·‌·‌·‌·‌</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,2,1][0,4,2][1,0,4][2,0,8][2,2,9][3,0,10][3,1,11][4,0,12][4,1,13][4,2,14][4,3,15][4,4,16][4,5,17][4,6,18][4,7,19][4,8,20][4,9,21][5,0,22][5,2,23][6,0,24][6,2,25][6,4,26][7,0,28][7,2,29][7,4,30][7,6,31][8,0,32][8,2,33][8,4,34][8,6,35][8,8,36]]
    ),
  )
}

///|
test "ws-faux-indent" {
  let out = mr(
    "\t\t  Hello world! \t  \t   \t    ",
    [p(4, 1), p(6, 2), p(29, 3)],
    faux_indent_length=2,
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="">        </span><span class="mtkz" style="width:20px">·‌·‌</span><span class="mtk2">He</span><span class="mtk3">llo world!</span><span class="mtkz" style="width:20px">·‌￫</span><span class="mtkz" style="width:40px">·‌·‌→ </span><span class="mtkz" style="width:40px">·‌·‌·‌￫</span><span class="mtkz" style="width:40px">·‌·‌·‌·‌</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,4,4][1,0,8][1,2,9][2,0,10][2,1,11][3,0,12][3,1,13][3,2,14][3,3,15][3,4,16][3,5,17][3,6,18][3,7,19][3,8,20][3,9,21][4,0,22][4,2,23][5,0,24][5,2,25][5,4,26][6,0,28][6,2,29][6,4,30][6,6,31][7,0,32][7,2,33][7,4,34][7,6,35][7,8,36]]
    ),
  )
}

///|
test "ws-monospace" {
  let out = mr(
    "\t\t  Hello world! \t  \t   \t    ",
    [p(4, 1), p(6, 2), p(29, 3)],
    use_monospace_optimizations=true,
    faux_indent_length=2,
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="">        </span><span class="mtkw">·‌·‌</span><span class="mtk2">He</span><span class="mtk3">llo world!</span><span class="mtkw">·‌￫·‌·‌→ ·‌·‌·‌￫·‌·‌·‌·‌</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,4,4][1,0,8][1,2,9][2,0,10][2,1,11][3,0,12][3,1,13][3,2,14][3,3,15][3,4,16][3,5,17][3,6,18][3,7,19][3,8,20][3,9,21][4,0,22][4,2,23][4,3,24][4,5,25][4,7,26][4,9,28][4,11,29][4,13,30][4,15,31][4,16,32][4,18,33][4,20,34][4,22,35][4,24,36]]
    ),
  )
}

///|
test "ws-middle" {
  let out = mr(
    "it  it it  it",
    [p(6, 1), p(7, 2), p(13, 3)],
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="mtk1">it</span><span class="mtkz" style="width:20px">·‌·‌</span><span class="mtk1">it</span><span class="mtk2"> </span><span class="mtk3">it</span><span class="mtkz" style="width:20px">·‌·‌</span><span class="mtk3">it</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][1,0,2][1,2,3][2,0,4][2,1,5][3,0,6][4,0,7][4,1,8][5,0,9][5,2,10][6,0,11][6,1,12][6,2,13]]
    ),
  )
}

///|
test "ws-all-middle" {
  let out = mr(
    " Hello world!\t",
    [p(4, 0), p(6, 1), p(14, 2)],
    render_whitespace=All,
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:10px">·‌</span><span class="mtk0">Hel</span><span class="mtk1">lo</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk2">world!</span><span class="mtkz" style="width:30px">→  </span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][1,1,2][1,2,3][2,0,4][2,1,5][3,0,6][4,0,7][4,1,8][4,2,9][4,3,10][4,4,11][4,5,12][5,0,13][5,3,16]]
    ),
  )
}

///|
test "ws-trail-no-trail" {
  let out = mr(
    " Hello world!",
    [p(4, 0), p(6, 1), p(14, 2)],
    render_whitespace=Trailing,
  )
  assert_html(
    out,
    (
      #|<span class="mtk0"> Hel</span><span class="mtk1">lo</span><span class="mtk2"> world!</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][1,0,4][1,1,5][2,0,6][2,1,7][2,2,8][2,3,9][2,4,10][2,5,11][2,6,12][2,7,13]]
    ),
  )
}

///|
test "ws-trail-with-trail" {
  let out = mr(
    " Hello world! \t",
    [p(4, 0), p(6, 1), p(15, 2)],
    render_whitespace=Trailing,
  )
  assert_html(
    out,
    (
      #|<span class="mtk0"> Hel</span><span class="mtk1">lo</span><span class="mtk2"> world!</span><span class="mtkz" style="width:30px">·‌→ </span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][1,0,4][1,1,5][2,0,6][2,1,7][2,2,8][2,3,9][2,4,10][2,5,11][2,6,12][3,0,13][3,2,14][3,4,16]]
    ),
  )
}

///|
test "ws-trail-8-8" {
  let out = mr(
    "        Hello world!        ",
    [p(8, 1), p(10, 2), p(28, 3)],
    render_whitespace=Trailing,
  )
  assert_html(
    out,
    (
      #|<span class="mtk1">        </span><span class="mtk2">He</span><span class="mtk3">llo world!</span><span class="mtkz" style="width:40px">·‌·‌·‌·‌</span><span class="mtkz" style="width:40px">·‌·‌·‌·‌</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][1,0,8][1,1,9][2,0,10][2,1,11][2,2,12][2,3,13][2,4,14][2,5,15][2,6,16][2,7,17][2,8,18][2,9,19][3,0,20][3,2,21][3,4,22][3,6,23][4,0,24][4,2,25][4,4,26][4,6,27][4,8,28]]
    ),
  )
}

///|
test "ws-trail-only" {
  let out = mr(" \t ", [p(2, 0), p(3, 1)], render_whitespace=Trailing)
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:40px">·‌→  </span><span class="mtkz" style="width:10px">·‌</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,2,1][1,0,4][1,2,5]]
    ),
  )
}

///|
test "ws-sel-none" {
  let out = mr(
    " Hello world!\t",
    [p(4, 0), p(6, 1), p(14, 2)],
    render_whitespace=Selection,
  )
  assert_html(
    out,
    (
      #|<span class="mtk0"> Hel</span><span class="mtk1">lo</span><span class="mtk2"> world!   </span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][1,0,4][1,1,5][2,0,6][2,1,7][2,2,8][2,3,9][2,4,10][2,5,11][2,6,12][2,7,13][2,10,16]]
    ),
  )
}

///|
test "ws-sel-whole" {
  let out = mr(
    " Hello world!\t",
    [p(4, 0), p(6, 1), p(14, 2)],
    render_whitespace=Selection,
    selections_on_line=[sel(0, 14)],
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:10px">·‌</span><span class="mtk0">Hel</span><span class="mtk1">lo</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk2">world!</span><span class="mtkz" style="width:30px">→  </span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][1,1,2][1,2,3][2,0,4][2,1,5][3,0,6][4,0,7][4,1,8][4,2,9][4,3,10][4,4,11][4,5,12][5,0,13][5,3,16]]
    ),
  )
}

///|
test "ws-sel-partial" {
  let out = mr(
    " Hello world!\t",
    [p(4, 0), p(6, 1), p(14, 2)],
    render_whitespace=Selection,
    selections_on_line=[sel(0, 5)],
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:10px">·‌</span><span class="mtk0">Hel</span><span class="mtk1">lo</span><span class="mtk2"> world!   </span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][1,1,2][1,2,3][2,0,4][2,1,5][3,0,6][3,1,7][3,2,8][3,3,9][3,4,10][3,5,11][3,6,12][3,7,13][3,10,16]]
    ),
  )
}

///|
test "ws-sel-multiple" {
  let out = mr(
    " Hello world!\t",
    [p(4, 0), p(6, 1), p(14, 2)],
    render_whitespace=Selection,
    selections_on_line=[sel(0, 5), sel(9, 14)],
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:10px">·‌</span><span class="mtk0">Hel</span><span class="mtk1">lo</span><span class="mtk2"> world!</span><span class="mtkz" style="width:30px">→  </span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][1,1,2][1,2,3][2,0,4][2,1,5][3,0,6][3,1,7][3,2,8][3,3,9][3,4,10][3,5,11][3,6,12][4,0,13][4,3,16]]
    ),
  )
}

///|
test "ws-sel-unsorted" {
  let out = mr(
    " Hello world!\t",
    [p(4, 0), p(6, 1), p(14, 2)],
    render_whitespace=Selection,
    selections_on_line=[sel(9, 14), sel(0, 5)],
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:10px">·‌</span><span class="mtk0">Hel</span><span class="mtk1">lo</span><span class="mtk2"> world!</span><span class="mtkz" style="width:30px">→  </span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][1,1,2][1,2,3][2,0,4][2,1,5][3,0,6][3,1,7][3,2,8][3,3,9][3,4,10][3,5,11][3,6,12][4,0,13][4,3,16]]
    ),
  )
}

///|
test "ws-sel-adjacent" {
  let out = mr(" * S", [p(4, 0)], render_whitespace=Selection, selections_on_line=[
    sel(0, 1),
    sel(1, 2),
    sel(2, 3),
  ])
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:10px">·‌</span><span class="mtk0">*</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk0">S</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][2,0,2][3,0,3][3,1,4]]
    ),
  )
}

///|
test "unsorted-deco" {
  let out = mr("Hello world", [p(11, 0)], line_decorations=[
    dec(5, 7, "a", Regular),
    dec(1, 3, "b", Regular),
    dec(2, 8, "c", Regular),
  ])
  assert_html(
    out,
    (
      #|<span class="mtk0 b">H</span><span class="mtk0 b c">e</span><span class="mtk0 c">ll</span><span class="mtk0 a c">o </span><span class="mtk0 c">w</span><span class="mtk0">orld</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][2,0,2][2,1,3][3,0,4][3,1,5][4,0,6][5,0,7][5,1,8][5,2,9][5,3,10][5,4,11]]
    ),
  )
}

///|
test "issue-11485" {
  let out = mr(
    "\tbla",
    [p(4, 3)],
    line_decorations=[dec(1, 2, "before", Before)],
    render_whitespace=All,
    font_ligatures=true,
  )
  assert_html(
    out,
    (
      #|<span class="mtkw before">→   </span><span class="mtk3">bla</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,4][1,1,5][1,2,6][1,3,7]]
    ),
  )
}

///|
test "issue-32436" {
  let out = mr(
    "\tbla",
    [p(4, 3)],
    line_decorations=[dec(2, 3, "before", Before)],
    render_whitespace=All,
    font_ligatures=true,
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:40px">→   </span><span class="mtk3 before">b</span><span class="mtk3">la</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,4][2,0,5][2,1,6][2,2,7]]
    ),
  )
}

///|
test "issue-30133" {
  let out = mr(
    "",
    [p(0, 3)],
    line_decorations=[dec(1, 2, "before", Before)],
    render_whitespace=All,
    font_ligatures=true,
  )
  assert_html(
    out,
    (
      #|<span class="before"></span>
    ),
  )
  assert_map(
    out,
    (
      #|[[1,0,0]]
    ),
  )
}

///|
test "issue-37208" {
  let out = mr(
    "  1. 🙏",
    [p("  1. 🙏".length(), 3)],
    line_decorations=[
      dec(
        "  1. 🙏".length(),
        "  1. 🙏".length() + 1,
        "inline-folded",
        After,
      ),
    ],
    is_basic_ascii=false,
    use_monospace_optimizations=true,
    tab_size=2,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">  1. </span><span class="mtk3 inline-folded">🙏</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][1,0,5][1,1,6][1,2,7]]
    ),
  )
}

///|
test "issue-37401" {
  let out = mr(
    "",
    [p(0, 3)],
    line_decorations=[dec(1, 1, "before", Before), dec(1, 1, "after", After)],
    use_monospace_optimizations=true,
    tab_size=2,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="before"></span><span class="after"></span>
    ),
  )
  assert_map(
    out,
    (
      #|[[1,0,0]]
    ),
  )
}

///|
test "issue-118759" {
  let out = mr(
    "",
    [p(0, 3)],
    line_decorations=[
      dec(1, 1, "after1", After),
      dec(1, 1, "after2", After),
      dec(1, 1, "before1", Before),
      dec(1, 1, "before2", Before),
    ],
    use_monospace_optimizations=true,
    tab_size=2,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="before1"></span><span class="before2"></span><span class="after1"></span><span class="after2"></span>
    ),
  )
  assert_map(
    out,
    (
      #|[[2,0,0]]
    ),
  )
}

///|
test "issue-38935" {
  let out = mr(
    "\t}",
    [p(2, 3)],
    line_decorations=[
      dec(
        3,
        3,
        "ced-TextEditorDecorationType2-5e9b9b3f-3 ced-TextEditorDecorationType2-3",
        Before,
      ),
      dec(
        3,
        3,
        "ced-TextEditorDecorationType2-5e9b9b3f-4 ced-TextEditorDecorationType2-4",
        After,
      ),
    ],
    use_monospace_optimizations=true,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">    }</span><span class="ced-TextEditorDecorationType2-5e9b9b3f-3 ced-TextEditorDecorationType2-3"></span><span class="ced-TextEditorDecorationType2-5e9b9b3f-4 ced-TextEditorDecorationType2-4"></span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,4,4][2,0,5]]
    ),
  )
}

///|
test "issue-136622" {
  let out = mr(
    "some text £",
    [p(11, 3)],
    line_decorations=[
      dec(5, 5, "inlineDec1", After),
      dec(6, 6, "inlineDec2", Before),
    ],
    is_basic_ascii=false,
    use_monospace_optimizations=true,
    stop_rendering_line_after=10000,
    render_control_characters=true,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">some</span><span class="mtk3 inlineDec1"></span><span class="mtk3"> </span><span class="mtk3 inlineDec2"></span><span class="mtk3">text £</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][1,0,4][4,0,5][4,1,6][4,2,7][4,3,8][4,4,9][4,5,10][4,6,11]]
    ),
  )
}

///|
test "issue-22832-1" {
  let out = mr(
    "asd = \"擦\"\t\t#asd",
    [p(15, 3)],
    is_basic_ascii=false,
    use_monospace_optimizations=true,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">asd = "擦"      #asd</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,9][0,9,10][0,11,12][0,15,16][0,16,17][0,17,18][0,18,19][0,19,20]]
    ),
  )
}

///|
test "issue-22832-2" {
  let out = mr(
    "asd = \"擦\"\t\t#asd",
    [p(15, 3)],
    is_basic_ascii=false,
    use_monospace_optimizations=true,
    stop_rendering_line_after=10000,
    render_whitespace=All,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">asd</span><span class="mtkw">·‌</span><span class="mtk3">=</span><span class="mtkw">·‌</span><span class="mtk3">"擦"</span><span class="mtkw">→ →   </span><span class="mtk3">#asd</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][1,0,3][2,0,4][3,0,5][4,0,6][4,1,7][4,2,9][5,0,10][5,2,12][6,0,16][6,1,17][6,2,18][6,3,19][6,4,20]]
    ),
  )
}

///|
test "issue-22352-2" {
  let out = mr(
    " JoyShareல் பின்தொடர்ந்து, விடீயோ, ஜோக்குகள், அனிமேசன், நகைச்சுவை படங்கள் மற்றும் செய்திகளை பெறுவீர்",
    [p(100, 3)],
    is_basic_ascii=false,
    use_monospace_optimizations=true,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3"> JoyShareல் பின்தொடர்ந்து, விடீயோ, ஜோக்குகள், </span><span class="mtk3">அனிமேசன், நகைச்சுவை படங்கள் மற்றும் செய்திகளை </span><span class="mtk3">பெறுவீர்</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][0,21,21][0,22,22][0,23,23][0,24,24][0,25,25][0,26,26][0,27,27][0,28,28][0,29,29][0,30,30][0,31,31][0,32,32][0,33,33][0,34,34][0,35,35][0,36,36][0,37,37][0,38,38][0,39,39][0,40,40][0,41,41][0,42,42][0,43,43][0,44,44][0,45,45][1,0,46][1,1,47][1,2,48][1,3,49][1,4,50][1,5,51][1,6,52][1,7,53][1,8,54][1,9,55][1,10,56][1,11,57][1,12,58][1,13,59][1,14,60][1,15,61][1,16,62][1,17,63][1,18,64][1,19,65][1,20,66][1,21,67][1,22,68][1,23,69][1,24,70][1,25,71][1,26,72][1,27,73][1,28,74][1,29,75][1,30,76][1,31,77][1,32,78][1,33,79][1,34,80][1,35,81][1,36,82][1,37,83][1,38,84][1,39,85][1,40,86][1,41,87][1,42,88][1,43,89][1,44,90][1,45,91][2,0,92][2,1,93][2,2,94][2,3,95][2,4,96][2,5,97][2,6,98][2,7,99][2,8,100]]
    ),
  )
}

///|
test "issue-42700" {
  let out = mr(
    " वो ऐसा क्या है जो हमारे अंदर भी है और बाहर भी है। जिसकी वजह से हम सब हैं। जिसने इस सृष्टि की रचना की है।",
    [p(105, 3)],
    is_basic_ascii=false,
    use_monospace_optimizations=true,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3"> वो ऐसा क्या है जो हमारे अंदर भी है और बाहर भी है। </span><span class="mtk3">जिसकी वजह से हम सब हैं। जिसने इस सृष्टि की रचना की </span><span class="mtk3">है।</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][0,21,21][0,22,22][0,23,23][0,24,24][0,25,25][0,26,26][0,27,27][0,28,28][0,29,29][0,30,30][0,31,31][0,32,32][0,33,33][0,34,34][0,35,35][0,36,36][0,37,37][0,38,38][0,39,39][0,40,40][0,41,41][0,42,42][0,43,43][0,44,44][0,45,45][0,46,46][0,47,47][0,48,48][0,49,49][0,50,50][1,0,51][1,1,52][1,2,53][1,3,54][1,4,55][1,5,56][1,6,57][1,7,58][1,8,59][1,9,60][1,10,61][1,11,62][1,12,63][1,13,64][1,14,65][1,15,66][1,16,67][1,17,68][1,18,69][1,19,70][1,20,71][1,21,72][1,22,73][1,23,74][1,24,75][1,25,76][1,26,77][1,27,78][1,28,79][1,29,80][1,30,81][1,31,82][1,32,83][1,33,84][1,34,85][1,35,86][1,36,87][1,37,88][1,38,89][1,39,90][1,40,91][1,41,92][1,42,93][1,43,94][1,44,95][1,45,96][1,46,97][1,47,98][1,48,99][1,49,100][1,50,101][2,0,102][2,1,103][2,2,104][2,3,105]]
    ),
  )
}

///|
test "issue-38123" {
  let out = mr(
    "This is a long line which never uses more than two spaces. ",
    [p(59, 3)],
    continues_with_wrapped_line=true,
    use_monospace_optimizations=true,
    stop_rendering_line_after=10000,
    render_whitespace=Boundary,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">This is a long line which never uses more than two</span><span class="mtk3"> spaces.</span><span class="mtk3"> </span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][0,21,21][0,22,22][0,23,23][0,24,24][0,25,25][0,26,26][0,27,27][0,28,28][0,29,29][0,30,30][0,31,31][0,32,32][0,33,33][0,34,34][0,35,35][0,36,36][0,37,37][0,38,38][0,39,39][0,40,40][0,41,41][0,42,42][0,43,43][0,44,44][0,45,45][0,46,46][0,47,47][0,48,48][0,49,49][1,0,50][1,1,51][1,2,52][1,3,53][1,4,54][1,5,55][1,6,56][1,7,57][2,0,58][2,1,59]]
    ),
  )
}

///|
test "issue-33525-1" {
  let out = mr(
    "append data to append data to append data to append data to append data to append data to append data to append data to append data to append data to append data to append data to append data to",
    [p(194, 3)],
    can_use_halfwidth_rightwards_arrow=false,
    font_ligatures=true,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">append data to append data to append data to </span><span class="mtk3">append data to append data to append data to </span><span class="mtk3">append data to append data to append data to </span><span class="mtk3">append data to append data to append data to </span><span class="mtk3">append data to</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][0,21,21][0,22,22][0,23,23][0,24,24][0,25,25][0,26,26][0,27,27][0,28,28][0,29,29][0,30,30][0,31,31][0,32,32][0,33,33][0,34,34][0,35,35][0,36,36][0,37,37][0,38,38][0,39,39][0,40,40][0,41,41][0,42,42][0,43,43][0,44,44][1,0,45][1,1,46][1,2,47][1,3,48][1,4,49][1,5,50][1,6,51][1,7,52][1,8,53][1,9,54][1,10,55][1,11,56][1,12,57][1,13,58][1,14,59][1,15,60][1,16,61][1,17,62][1,18,63][1,19,64][1,20,65][1,21,66][1,22,67][1,23,68][1,24,69][1,25,70][1,26,71][1,27,72][1,28,73][1,29,74][1,30,75][1,31,76][1,32,77][1,33,78][1,34,79][1,35,80][1,36,81][1,37,82][1,38,83][1,39,84][1,40,85][1,41,86][1,42,87][1,43,88][1,44,89][2,0,90][2,1,91][2,2,92][2,3,93][2,4,94][2,5,95][2,6,96][2,7,97][2,8,98][2,9,99][2,10,100][2,11,101][2,12,102][2,13,103][2,14,104][2,15,105][2,16,106][2,17,107][2,18,108][2,19,109][2,20,110][2,21,111][2,22,112][2,23,113][2,24,114][2,25,115][2,26,116][2,27,117][2,28,118][2,29,119][2,30,120][2,31,121][2,32,122][2,33,123][2,34,124][2,35,125][2,36,126][2,37,127][2,38,128][2,39,129][2,40,130][2,41,131][2,42,132][2,43,133][2,44,134][3,0,135][3,1,136][3,2,137][3,3,138][3,4,139][3,5,140][3,6,141][3,7,142][3,8,143][3,9,144][3,10,145][3,11,146][3,12,147][3,13,148][3,14,149][3,15,150][3,16,151][3,17,152][3,18,153][3,19,154][3,20,155][3,21,156][3,22,157][3,23,158][3,24,159][3,25,160][3,26,161][3,27,162][3,28,163][3,29,164][3,30,165][3,31,166][3,32,167][3,33,168][3,34,169][3,35,170][3,36,171][3,37,172][3,38,173][3,39,174][3,40,175][3,41,176][3,42,177][3,43,178][3,44,179][4,0,180][4,1,181][4,2,182][4,3,183][4,4,184][4,5,185][4,6,186][4,7,187][4,8,188][4,9,189][4,10,190][4,11,191][4,12,192][4,13,193][4,14,194]]
    ),
  )
}

///|
test "issue-33525-2" {
  let out = mr(
    "appenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatato",
    [p(194, 3)],
    can_use_halfwidth_rightwards_arrow=false,
    font_ligatures=true,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">appenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatatoappenddatato</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][0,21,21][0,22,22][0,23,23][0,24,24][0,25,25][0,26,26][0,27,27][0,28,28][0,29,29][0,30,30][0,31,31][0,32,32][0,33,33][0,34,34][0,35,35][0,36,36][0,37,37][0,38,38][0,39,39][0,40,40][0,41,41][0,42,42][0,43,43][0,44,44][0,45,45][0,46,46][0,47,47][0,48,48][0,49,49][0,50,50][0,51,51][0,52,52][0,53,53][0,54,54][0,55,55][0,56,56][0,57,57][0,58,58][0,59,59][0,60,60][0,61,61][0,62,62][0,63,63][0,64,64][0,65,65][0,66,66][0,67,67][0,68,68][0,69,69][0,70,70][0,71,71][0,72,72][0,73,73][0,74,74][0,75,75][0,76,76][0,77,77][0,78,78][0,79,79][0,80,80][0,81,81][0,82,82][0,83,83][0,84,84][0,85,85][0,86,86][0,87,87][0,88,88][0,89,89][0,90,90][0,91,91][0,92,92][0,93,93][0,94,94][0,95,95][0,96,96][0,97,97][0,98,98][0,99,99][0,100,100][0,101,101][0,102,102][0,103,103][0,104,104][0,105,105][0,106,106][0,107,107][0,108,108][0,109,109][0,110,110][0,111,111][0,112,112][0,113,113][0,114,114][0,115,115][0,116,116][0,117,117][0,118,118][0,119,119][0,120,120][0,121,121][0,122,122][0,123,123][0,124,124][0,125,125][0,126,126][0,127,127][0,128,128][0,129,129][0,130,130][0,131,131][0,132,132][0,133,133][0,134,134][0,135,135][0,136,136][0,137,137][0,138,138][0,139,139][0,140,140][0,141,141][0,142,142][0,143,143][0,144,144][0,145,145][0,146,146][0,147,147][0,148,148][0,149,149][0,150,150][0,151,151][0,152,152][0,153,153][0,154,154][0,155,155][0,156,156]]
    ),
  )
}

///|
test "issue-91936" {
  let out = mr(
    "                    else if ($s = 08) then '\\b'",
    [
      p(20, 1),
      p(24, 15),
      p(25, 1),
      p(27, 15),
      p(28, 1),
      p(29, 1),
      p(31, 16),
      p(32, 1),
      p(33, 1),
      p(34, 1),
      p(36, 6),
      p(37, 1),
      p(38, 1),
      p(42, 15),
      p(43, 1),
      p(47, 11),
    ],
    stop_rendering_line_after=10000,
    render_whitespace=Selection,
    middot_width=11.0,
    wsmiddot_width=11.0,
    selections_on_line=[sel(0, 47)],
  )
  assert_html(
    out,
    (
      #|<span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk15">else</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk15">if</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk1">(</span><span class="mtk16">$s</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk1">=</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk6">08</span><span class="mtk1">)</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk15">then</span><span class="mtkz" style="width:10px">·‌</span><span class="mtk11">'\b'</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][1,0,1][2,0,2][3,0,3][4,0,4][5,0,5][6,0,6][7,0,7][8,0,8][9,0,9][10,0,10][11,0,11][12,0,12][13,0,13][14,0,14][15,0,15][16,0,16][17,0,17][18,0,18][19,0,19][20,0,20][20,1,21][20,2,22][20,3,23][21,0,24][22,0,25][22,1,26][23,0,27][24,0,28][25,0,29][25,1,30][26,0,31][27,0,32][28,0,33][29,0,34][29,1,35][30,0,36][31,0,37][32,0,38][32,1,39][32,2,40][32,3,41][33,0,42][34,0,43][34,1,44][34,2,45][34,3,46][34,4,47]]
    ),
  )
}

///|
test "issue-119416" {
  let out = mr(
    "[\u{007F}] [\u{0000}]",
    [p(7, 3)],
    can_use_halfwidth_rightwards_arrow=false,
    stop_rendering_line_after=10000,
    render_control_characters=true,
    font_ligatures=true,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">[␡] [␀]</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7]]
    ),
  )
}

///|
test "issue-116939" {
  let out = mr(
    "transferBalance(5678,\u{202E}6776,4321\u{202C},\"USD\");",
    [p(42, 3)],
    can_use_halfwidth_rightwards_arrow=false,
    is_basic_ascii=false,
    stop_rendering_line_after=10000,
    render_control_characters=true,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">transferBalance(5678,</span><span class="mtkcontrol">[U+202E]</span><span class="mtk3">6776,4321</span><span class="mtkcontrol">[U+202C]</span><span class="mtk3">,"USD");</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][1,0,21][2,0,29][2,1,30][2,2,31][2,3,32][2,4,33][2,5,34][2,6,35][2,7,36][2,8,37][3,0,38][4,0,46][4,1,47][4,2,48][4,3,49][4,4,50][4,5,51][4,6,52][4,7,53][4,8,54]]
    ),
  )
}

///|
test "issue-124038" {
  let out = mr(
    "    if",
    [p(4, 1), p(6, 2)],
    line_decorations=[
      dec(
        7,
        7,
        "ced-1-TextEditorDecorationType2-17c14d98-3 ced-1-TextEditorDecorationType2-3",
        Before,
      ),
      dec(
        7,
        7,
        "ced-1-TextEditorDecorationType2-17c14d98-4 ced-1-TextEditorDecorationType2-4",
        After,
      ),
      dec(7, 7, "ced-ghost-text-1-4", After),
    ],
    use_monospace_optimizations=true,
    can_use_halfwidth_rightwards_arrow=false,
    stop_rendering_line_after=10000,
    render_whitespace=All,
  )
  assert_html(
    out,
    (
      #|<span class="mtkw">·‌·‌·‌·‌</span><span class="mtk2">if</span><span class="ced-1-TextEditorDecorationType2-17c14d98-3 ced-1-TextEditorDecorationType2-3"></span><span class="ced-1-TextEditorDecorationType2-17c14d98-4 ced-1-TextEditorDecorationType2-4"></span><span class="ced-ghost-text-1-4"></span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,2,1][0,4,2][0,6,3][1,0,4][1,1,5][3,0,6]]
    ),
  )
}

///|
test "issue-20624" {
  let out = mr(
    "a𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷",
    [p(241, 1)],
    is_basic_ascii=false,
  )
  assert_html(
    out,
    (
      #|<span class="mtk1">a𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷𠮷</span>
    ),
  )
}

///|
test "issue-22352-1" {
  let out = mr(
    "12345689012345678901234568901234567890123456890abába",
    [p(53, 3)],
    is_basic_ascii=false,
    use_monospace_optimizations=true,
    stop_rendering_line_after=10000,
  )
  assert_html(
    out,
    (
      #|<span class="mtk3">12345689012345678901234568901234567890123456890abába</span>
    ),
  )
  assert_map(
    out,
    (
      #|[[0,0,0][0,1,1][0,2,2][0,3,3][0,4,4][0,5,5][0,6,6][0,7,7][0,8,8][0,9,9][0,10,10][0,11,11][0,12,12][0,13,13][0,14,14][0,15,15][0,16,16][0,17,17][0,18,18][0,19,19][0,20,20][0,21,21][0,22,22][0,23,23][0,24,24][0,25,25][0,26,26][0,27,27][0,28,28][0,29,29][0,30,30][0,31,31][0,32,32][0,33,33][0,34,34][0,35,35][0,36,36][0,37,37][0,38,38][0,39,39][0,40,40][0,41,41][0,42,42][0,43,43][0,44,44][0,45,45][0,46,46][0,47,47][0,48,48][0,49,49][0,50,50][0,51,51][0,52,52][0,53,53]]
    ),
  )
}

///|
test "issue-6885" {
  assert_html(
    mr("This is just a long line that contains very inter", [p(49, 1)]),
    (
      #|<span class="mtk1">This is just a long line that contains very inter</span>
    ),
  )
  assert_html(
    mr("This is just a long line that contains very intere", [p(50, 1)]),
    (
      #|<span class="mtk1">This is just a long line that contains very intere</span>
    ),
  )
  assert_html(
    mr("This is just a long line that contains very interes", [p(51, 1)]),
    (
      #|<span class="mtk1">This is just a long line that contains very intere</span><span class="mtk1">s</span>
    ),
  )
  assert_html(
    mr(
      "This is just a long line that contains very interesting text. This is just a long line that contain",
      [p(99, 1)],
    ),
    (
      #|<span class="mtk1">This is just a long line that contains very intere</span><span class="mtk1">sting text. This is just a long line that contain</span>
    ),
  )
  assert_html(
    mr(
      "This is just a long line that contains very interesting text. This is just a long line that contains",
      [p(100, 1)],
    ),
    (
      #|<span class="mtk1">This is just a long line that contains very intere</span><span class="mtk1">sting text. This is just a long line that contains</span>
    ),
  )
  assert_html(
    mr(
      "This is just a long line that contains very interesting text. This is just a long line that contains ",
      [p(101, 1)],
    ),
    (
      #|<span class="mtk1">This is just a long line that contains very intere</span><span class="mtk1">sting text. This is just a long line that contains</span><span class="mtk1"> </span>
    ),
  )
}

///|
test "issue-21476" {
  assert_html(
    mr(
      "This is just a long line that contains very interesting text. This is just a long line that contains ",
      [p(101, 1)],
      font_ligatures=true,
    ),
    (
      #|<span class="mtk1">This is just a long line that contains very </span><span class="mtk1">interesting text. This is just a long line that </span><span class="mtk1">contains </span>
    ),
  )
}

///|
test "getColumnOfLinePartOffset 1 - simple text" {
  let out = mr("hello world", [p(11, 1)], tab_size=4)
  assert_get_column(out, 0, 11, 0, 1)
  assert_get_column(out, 0, 11, 1, 2)
  assert_get_column(out, 0, 11, 2, 3)
  assert_get_column(out, 0, 11, 3, 4)
  assert_get_column(out, 0, 11, 4, 5)
  assert_get_column(out, 0, 11, 5, 6)
  assert_get_column(out, 0, 11, 6, 7)
  assert_get_column(out, 0, 11, 7, 8)
  assert_get_column(out, 0, 11, 8, 9)
  assert_get_column(out, 0, 11, 9, 10)
  assert_get_column(out, 0, 11, 10, 11)
  assert_get_column(out, 0, 11, 11, 12)
}

///|
test "getColumnOfLinePartOffset 2 - regular JS" {
  let out = mr(
    "var x = 3;",
    [p(3, 1), p(4, 2), p(5, 3), p(8, 4), p(9, 5), p(10, 6)],
    tab_size=4,
  )
  assert_get_column(out, 0, 3, 0, 1)
  assert_get_column(out, 0, 3, 1, 2)
  assert_get_column(out, 0, 3, 2, 3)
  assert_get_column(out, 0, 3, 3, 4)
  assert_get_column(out, 1, 1, 0, 4)
  assert_get_column(out, 1, 1, 1, 5)
  assert_get_column(out, 2, 1, 0, 5)
  assert_get_column(out, 2, 1, 1, 6)
  assert_get_column(out, 3, 3, 0, 6)
  assert_get_column(out, 3, 3, 1, 7)
  assert_get_column(out, 3, 3, 2, 8)
  assert_get_column(out, 3, 3, 3, 9)
  assert_get_column(out, 4, 1, 0, 9)
  assert_get_column(out, 4, 1, 1, 10)
  assert_get_column(out, 5, 1, 0, 10)
  assert_get_column(out, 5, 1, 1, 11)
}

///|
test "getColumnOfLinePartOffset 3 - tab with tab size 6" {
  let out = mr("\t", [p(1, 1)], tab_size=6)
  assert_get_column(out, 0, 6, 0, 1)
  assert_get_column(out, 0, 6, 1, 1)
  assert_get_column(out, 0, 6, 2, 1)
  assert_get_column(out, 0, 6, 3, 1)
  assert_get_column(out, 0, 6, 4, 2)
  assert_get_column(out, 0, 6, 5, 2)
  assert_get_column(out, 0, 6, 6, 2)
}

///|
test "getColumnOfLinePartOffset 4 - once indented line, tab size 4" {
  let out = mr("\tfunction", [p(1, 1), p(9, 2)], tab_size=4)
  assert_get_column(out, 0, 4, 0, 1)
  assert_get_column(out, 0, 4, 1, 1)
  assert_get_column(out, 0, 4, 2, 1)
  assert_get_column(out, 0, 4, 3, 2)
  assert_get_column(out, 0, 4, 4, 2)
  assert_get_column(out, 1, 8, 0, 2)
  assert_get_column(out, 1, 8, 1, 3)
  assert_get_column(out, 1, 8, 2, 4)
  assert_get_column(out, 1, 8, 3, 5)
  assert_get_column(out, 1, 8, 4, 6)
  assert_get_column(out, 1, 8, 5, 7)
  assert_get_column(out, 1, 8, 6, 8)
  assert_get_column(out, 1, 8, 7, 9)
  assert_get_column(out, 1, 8, 8, 10)
}

///|
test "getColumnOfLinePartOffset 5 - twice indented line, tab size 4" {
  let out = mr("\t\tfunction", [p(2, 1), p(10, 2)], tab_size=4)
  assert_get_column(out, 0, 8, 0, 1)
  assert_get_column(out, 0, 8, 1, 1)
  assert_get_column(out, 0, 8, 2, 1)
  assert_get_column(out, 0, 8, 3, 2)
  assert_get_column(out, 0, 8, 4, 2)
  assert_get_column(out, 0, 8, 5, 2)
  assert_get_column(out, 0, 8, 6, 2)
  assert_get_column(out, 0, 8, 7, 3)
  assert_get_column(out, 0, 8, 8, 3)
  assert_get_column(out, 1, 8, 0, 3)
  assert_get_column(out, 1, 8, 1, 4)
  assert_get_column(out, 1, 8, 2, 5)
  assert_get_column(out, 1, 8, 3, 6)
  assert_get_column(out, 1, 8, 4, 7)
  assert_get_column(out, 1, 8, 5, 8)
  assert_get_column(out, 1, 8, 6, 9)
  assert_get_column(out, 1, 8, 7, 10)
  assert_get_column(out, 1, 8, 8, 11)
}

// ===========================================================================
// helpers
// ===========================================================================

///|
fn segment(
  start_offset : Int,
  end_offset : Int,
  class_name : String,
  metadata? : Int = 0,
) -> @view_layout.DecorationSegment {
  { start_offset, end_offset, class_name, metadata, }
}

///|
fn assert_segments(
  name : String,
  actual : Array[@view_layout.DecorationSegment],
  expected : Array[@view_layout.DecorationSegment],
) -> Unit raise {
  guard actual == expected else {
    fail("Monaco lineDecorations port failed: \{name}")
  }
}

///|
/// A token part `mtk<cls>` ending at `end_index` (Monaco's `createPart`).
fn p(end_index : Int, cls : Int) -> @view_layout.LinePart {
  LinePart(end_index, "mtk\{cls.to_string()}")
}

///|
/// A line decoration (Monaco's `new LineDecoration`).
fn dec(
  start_column : Int,
  end_column : Int,
  class_name : String,
  decoration_type : @view_layout.InlineDecorationType,
) -> @view_layout.LineDecoration {
  LineDecoration(start_column, end_column, class_name, decoration_type~)
}

///|
/// An on-line selection range (Monaco's `new OffsetRange`).
fn sel(start : Int, end_exclusive : Int) -> @base_common.OffsetRange {
  OffsetRange(start, end_exclusive)
}

///|
/// Builds a render input mirroring Monaco's test defaults (space/middot widths
/// of 10).
fn monaco_input(
  content : String,
  tokens : Array[@view_layout.LinePart],
  line_decorations? : Array[@view_layout.LineDecoration] = [],
  tab_size? : Int = 4,
  contains_rtl? : Bool = false,
  is_basic_ascii? : Bool = true,
  continues_with_wrapped_line? : Bool = false,
  use_monospace_optimizations? : Bool = false,
  can_use_halfwidth_rightwards_arrow? : Bool = true,
  faux_indent_length? : Int = 0,
  stop_rendering_line_after? : Int = -1,
  render_whitespace? : @editor_api.RenderWhitespace = None,
  render_control_characters? : Bool = false,
  font_ligatures? : Bool = false,
  space_width? : Double = 10.0,
  middot_width? : Double = 10.0,
  wsmiddot_width? : Double = 10.0,
  selections_on_line? : Array[@base_common.OffsetRange] = [],
) -> @view_layout.RenderLineInput {
  let data : @view_layout.ViewLineRenderingData = {
    min_column: 1,
    max_column: content.length() + 1,
    content,
    continues_with_wrapped_line,
    contains_rtl,
    is_basic_ascii,
    tokens,
    inline_decorations: [],
    tab_size,
    start_visible_column: 0,
    text_direction: LTR,
    has_variable_fonts: false,
  }
  @view_layout.RenderLineInput::from_view_line(
    data,
    line_decorations~,
    use_monospace_optimizations~,
    can_use_halfwidth_rightwards_arrow~,
    faux_indent_length~,
    space_width~,
    middot_width~,
    wsmiddot_width~,
    stop_rendering_line_after~,
    render_whitespace~,
    render_control_characters~,
    font_ligatures~,
    selections_on_line~,
  )
}

///|
/// Renders one line with Monaco's test defaults (`renderViewLine`).
fn mr(
  content : String,
  tokens : Array[@view_layout.LinePart],
  line_decorations? : Array[@view_layout.LineDecoration] = [],
  tab_size? : Int = 4,
  contains_rtl? : Bool = false,
  is_basic_ascii? : Bool = true,
  continues_with_wrapped_line? : Bool = false,
  use_monospace_optimizations? : Bool = false,
  can_use_halfwidth_rightwards_arrow? : Bool = true,
  faux_indent_length? : Int = 0,
  stop_rendering_line_after? : Int = -1,
  render_whitespace? : @editor_api.RenderWhitespace = None,
  render_control_characters? : Bool = false,
  font_ligatures? : Bool = false,
  space_width? : Double = 10.0,
  middot_width? : Double = 10.0,
  wsmiddot_width? : Double = 10.0,
  selections_on_line? : Array[@base_common.OffsetRange] = [],
) -> @view_layout.RenderLineOutput2 {
  @view_layout.render_view_line2(
    monaco_input(
      content,
      tokens,
      line_decorations~,
      tab_size~,
      contains_rtl~,
      is_basic_ascii~,
      continues_with_wrapped_line~,
      use_monospace_optimizations~,
      can_use_halfwidth_rightwards_arrow~,
      faux_indent_length~,
      stop_rendering_line_after~,
      render_whitespace~,
      render_control_characters~,
      font_ligatures~,
      space_width~,
      middot_width~,
      wsmiddot_width~,
      selections_on_line~,
    ),
  )
}

///|
/// Inner HTML with this package's `view-line-content` wrapper stripped, so it
/// matches Monaco's inflated snapshot HTML.
fn inner(out : @view_layout.RenderLineOutput2) -> String {
  let wrapper = "<span class=\"view-line-content\">"
  out.html[wrapper.length():out.html.length() - "</span>".length()].to_owned()
}

///|
/// The inflated `CharacterMapping` in Monaco's compact
/// `[partIndex,charIndex,visibleColumn]` form (the `*.1.snap` shape).
fn cmap(out : @view_layout.RenderLineOutput2) -> String {
  let sb = StringBuilder()
  sb.write_char('[')
  for entry in out.character_mapping.entries {
    sb <+ "[\{entry.part_index},\{entry.char_index},\{entry.visible_column}]"
  }
  sb.write_char(']')
  sb.to_string()
}

///|
/// Asserts the inner HTML equals Monaco's inflated snapshot HTML.
fn assert_html(
  out : @view_layout.RenderLineOutput2,
  expected : String,
) -> Unit raise {
  guard inner(out) == expected else {
    fail(
      (
        $|Monaco render html mismatch:
        $| got: \{inner(out)}
        $| exp: \{expected}
      ),
    )
  }
}

///|
/// Asserts the inflated mapping equals Monaco's snapshot and that it round-trips.
fn assert_map(
  out : @view_layout.RenderLineOutput2,
  expected : String,
) -> Unit raise {
  guard cmap(out) == expected else {
    fail(
      (
        $|Monaco render mapping mismatch:
        $| got: \{cmap(out)}
        $| exp: \{expected}
      ),
    )
  }
  let mapping = out.character_mapping
  let mut previous_horizontal_offset = -1
  for index in 0..<mapping.length {
    let column = index + 1
    let entry = mapping.entries[index]
    guard entry.visible_column >= previous_horizontal_offset else {
      fail("Monaco render mapping horizontal offset regressed")
    }
    let position = mapping.get_dom_position(column)
    guard position.part_index == entry.part_index &&
      position.char_index == entry.char_index else {
      fail("Monaco render getDomPosition mismatch")
    }
    previous_horizontal_offset = entry.visible_column
  }
}

///|
fn assert_get_column(
  out : @view_layout.RenderLineOutput2,
  part_index : Int,
  part_length : Int,
  char_index : Int,
  expected_column : Int,
) -> Unit raise {
  let actual = out.character_mapping.get_column(
    { part_index, char_index, },
    part_length,
  )
  guard actual == expected_column else {
    fail(
      "Monaco getColumn mismatch: part \{part_index} off \{char_index} -> \{actual} (want \{expected_column})",
    )
  }
}
