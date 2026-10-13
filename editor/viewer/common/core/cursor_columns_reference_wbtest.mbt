// White-box conformance port of Monaco/VS Code's CursorColumns suite.
//
// Ports: vscode/src/vs/editor/test/common/core/cursorColumns.test.ts
// From the checked-in vscode submodule.

///|
test "visibleColumnFromColumn" {
  fn t(
    text : String,
    tab_size : Int32,
    column : Int32,
    expected : Int32,
  ) -> Unit raise {
    assert_eq(visible_column_from_column(text, column, tab_size), expected)
  }

  t("\t\tvar x = 3;", 4, 1, 0)
  t("\t\tvar x = 3;", 4, 2, 4)
  t("\t\tvar x = 3;", 4, 3, 8)
  t("\t\tvar x = 3;", 4, 4, 9)
  t("\t\tvar x = 3;", 4, 5, 10)
  t("\t\tvar x = 3;", 4, 6, 11)
  t("\t\tvar x = 3;", 4, 7, 12)
  t("\t\tvar x = 3;", 4, 8, 13)
  t("\t\tvar x = 3;", 4, 9, 14)
  t("\t\tvar x = 3;", 4, 10, 15)
  t("\t\tvar x = 3;", 4, 11, 16)
  t("\t\tvar x = 3;", 4, 12, 17)
  t("\t\tvar x = 3;", 4, 13, 18)
  t("\t \tvar x = 3;", 4, 1, 0)
  t("\t \tvar x = 3;", 4, 2, 4)
  t("\t \tvar x = 3;", 4, 3, 5)
  t("\t \tvar x = 3;", 4, 4, 8)
  t("\t \tvar x = 3;", 4, 5, 9)
  t("\t \tvar x = 3;", 4, 6, 10)
  t("\t \tvar x = 3;", 4, 7, 11)
  t("\t \tvar x = 3;", 4, 8, 12)
  t("\t \tvar x = 3;", 4, 9, 13)
  t("\t \tvar x = 3;", 4, 10, 14)
  t("\t \tvar x = 3;", 4, 11, 15)
  t("\t \tvar x = 3;", 4, 12, 16)
  t("\t \tvar x = 3;", 4, 13, 17)
  t("\t \tvar x = 3;", 4, 14, 18)
  t("\t  \tx\t", 4, -1, 0)
  t("\t  \tx\t", 4, 0, 0)
  t("\t  \tx\t", 4, 1, 0)
  t("\t  \tx\t", 4, 2, 4)
  t("\t  \tx\t", 4, 3, 5)
  t("\t  \tx\t", 4, 4, 6)
  t("\t  \tx\t", 4, 5, 8)
  t("\t  \tx\t", 4, 6, 9)
  t("\t  \tx\t", 4, 7, 12)
  t("\t  \tx\t", 4, 8, 12)
  t("\t  \tx\t", 4, 9, 12)
  t("baz", 4, 1, 0)
  t("baz", 4, 2, 1)
  t("baz", 4, 3, 2)
  t("baz", 4, 4, 3)
  t("📚az", 4, 1, 0)
  t("📚az", 4, 2, 1)
  t("📚az", 4, 3, 2)
  t("📚az", 4, 4, 3)
  t("📚az", 4, 5, 4)
}

///|
test "toStatusbarColumn" {
  fn t(
    text : String,
    tab_size : Int32,
    column : Int32,
    expected : Int32,
  ) -> Unit raise {
    assert_eq(to_statusbar_column(text, column, tab_size), expected)
  }

  t("    spaces", 4, 1, 1)
  t("    spaces", 4, 2, 2)
  t("    spaces", 4, 3, 3)
  t("    spaces", 4, 4, 4)
  t("    spaces", 4, 5, 5)
  t("    spaces", 4, 6, 6)
  t("    spaces", 4, 7, 7)
  t("    spaces", 4, 8, 8)
  t("    spaces", 4, 9, 9)
  t("    spaces", 4, 10, 10)
  t("    spaces", 4, 11, 11)
  t("\ttab", 4, 1, 1)
  t("\ttab", 4, 2, 5)
  t("\ttab", 4, 3, 6)
  t("\ttab", 4, 4, 7)
  t("\ttab", 4, 5, 8)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 1, 1)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 2, 2)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 3, 2)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 4, 3)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 5, 3)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 6, 4)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 7, 4)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 8, 5)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 9, 5)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 10, 6)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 11, 6)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 12, 7)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 13, 7)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 14, 8)
  t("𐌀𐌁𐌂𐌃𐌄𐌅𐌆", 4, 15, 8)
  t("🎈🎈🎈🎈", 4, 1, 1)
  t("🎈🎈🎈🎈", 4, 2, 2)
  t("🎈🎈🎈🎈", 4, 3, 2)
  t("🎈🎈🎈🎈", 4, 4, 3)
  t("🎈🎈🎈🎈", 4, 5, 3)
  t("🎈🎈🎈🎈", 4, 6, 4)
  t("🎈🎈🎈🎈", 4, 7, 4)
  t("🎈🎈🎈🎈", 4, 8, 5)
  t("🎈🎈🎈🎈", 4, 9, 5)
  t("何何何何", 4, 1, 1)
  t("何何何何", 4, 2, 2)
  t("何何何何", 4, 3, 3)
  t("何何何何", 4, 4, 4)
}

///|
test "columnFromVisibleColumn" {
  fn t(
    text : String,
    tab_size : Int32,
    visible_column : Int32,
    expected : Int32,
  ) -> Unit raise {
    assert_eq(
      column_from_visible_column(text, visible_column, tab_size),
      expected,
    )
  }

  t("\t\tvar x = 3;", 4, 1, 1)
  t("\t\tvar x = 3;", 4, 2, 1)
  t("\t\tvar x = 3;", 4, 3, 2)
  t("\t\tvar x = 3;", 4, 4, 2)
  t("\t\tvar x = 3;", 4, 5, 2)
  t("\t\tvar x = 3;", 4, 6, 2)
  t("\t\tvar x = 3;", 4, 7, 3)
  t("\t\tvar x = 3;", 4, 8, 3)
  t("\t\tvar x = 3;", 4, 9, 4)
  t("\t\tvar x = 3;", 4, 10, 5)
  t("\t\tvar x = 3;", 4, 11, 6)
  t("\t\tvar x = 3;", 4, 12, 7)
  t("\t\tvar x = 3;", 4, 13, 8)
  t("\t\tvar x = 3;", 4, 14, 9)
  t("\t\tvar x = 3;", 4, 15, 10)
  t("\t\tvar x = 3;", 4, 16, 11)
  t("\t\tvar x = 3;", 4, 17, 12)
  t("\t\tvar x = 3;", 4, 18, 13)
  t("\t \tvar x = 3;", 4, 0, 1)
  t("\t \tvar x = 3;", 4, 1, 1)
  t("\t \tvar x = 3;", 4, 2, 1)
  t("\t \tvar x = 3;", 4, 3, 2)
  t("\t \tvar x = 3;", 4, 4, 2)
  t("\t \tvar x = 3;", 4, 5, 3)
  t("\t \tvar x = 3;", 4, 6, 3)
  t("\t \tvar x = 3;", 4, 7, 4)
  t("\t \tvar x = 3;", 4, 8, 4)
  t("\t \tvar x = 3;", 4, 9, 5)
  t("\t \tvar x = 3;", 4, 10, 6)
  t("\t \tvar x = 3;", 4, 11, 7)
  t("\t \tvar x = 3;", 4, 12, 8)
  t("\t \tvar x = 3;", 4, 13, 9)
  t("\t \tvar x = 3;", 4, 14, 10)
  t("\t \tvar x = 3;", 4, 15, 11)
  t("\t \tvar x = 3;", 4, 16, 12)
  t("\t \tvar x = 3;", 4, 17, 13)
  t("\t \tvar x = 3;", 4, 18, 14)
  t("\t  \tx\t", 4, -2, 1)
  t("\t  \tx\t", 4, -1, 1)
  t("\t  \tx\t", 4, 0, 1)
  t("\t  \tx\t", 4, 1, 1)
  t("\t  \tx\t", 4, 2, 1)
  t("\t  \tx\t", 4, 3, 2)
  t("\t  \tx\t", 4, 4, 2)
  t("\t  \tx\t", 4, 5, 3)
  t("\t  \tx\t", 4, 6, 4)
  t("\t  \tx\t", 4, 7, 4)
  t("\t  \tx\t", 4, 8, 5)
  t("\t  \tx\t", 4, 9, 6)
  t("\t  \tx\t", 4, 10, 6)
  t("\t  \tx\t", 4, 11, 7)
  t("\t  \tx\t", 4, 12, 7)
  t("\t  \tx\t", 4, 13, 7)
  t("\t  \tx\t", 4, 14, 7)
  t("baz", 4, 0, 1)
  t("baz", 4, 1, 2)
  t("baz", 4, 2, 3)
  t("baz", 4, 3, 4)
  t("📚az", 4, 0, 1)
  t("📚az", 4, 1, 1)
  t("📚az", 4, 2, 3)
  t("📚az", 4, 3, 4)
  t("📚az", 4, 4, 5)
}

///|
fn assert_next_tab_stop(f : (Int32, Int32) -> Int32) -> Unit raise {
  assert_eq(f(0, 4), 4)
  assert_eq(f(1, 4), 4)
  assert_eq(f(2, 4), 4)
  assert_eq(f(3, 4), 4)
  assert_eq(f(4, 4), 8)
  assert_eq(f(5, 4), 8)
  assert_eq(f(6, 4), 8)
  assert_eq(f(7, 4), 8)
  assert_eq(f(8, 4), 12)
  assert_eq(f(0, 2), 2)
  assert_eq(f(1, 2), 2)
  assert_eq(f(2, 2), 4)
  assert_eq(f(3, 2), 4)
  assert_eq(f(4, 2), 6)
  assert_eq(f(5, 2), 6)
  assert_eq(f(6, 2), 8)
  assert_eq(f(7, 2), 8)
  assert_eq(f(8, 2), 10)
  assert_eq(f(0, 1), 1)
  assert_eq(f(1, 1), 2)
  assert_eq(f(2, 1), 3)
  assert_eq(f(3, 1), 4)
  assert_eq(f(4, 1), 5)
  assert_eq(f(5, 1), 6)
  assert_eq(f(6, 1), 7)
  assert_eq(f(7, 1), 8)
  assert_eq(f(8, 1), 9)
}

///|
test "nextRenderTabStop" {
  assert_next_tab_stop(next_render_tab_stop)
}
