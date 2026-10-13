// The anchor-candidate pass and anchor semantics of
// `contentHoverWidgetWrapper._findHoverAnchorCandidates` /
// `hoverTypes.ts`'s `equals` / `canAdoptVisibleHover`, plus the marker
// participant's anchor-line column filter
// (`contentHoverComputer._getLineDecorations`). One case per
// behavior-switching branch.

///|
fn range_anchor(
  line : Int32,
  start_column : Int32,
  end_column : Int32,
) -> HoverAnchor {
  HoverRangeAnchor(
    priority=0,
    range=Range(line, start_column, line, end_column),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
}

///|
let test_foreign_owner : HoverParticipantOwner = HoverParticipantOwner()

///|
fn foreign_anchor(
  injected_text_index : Int32,
  supports_marker_hover~ : Bool = true,
  owner~ : HoverParticipantOwner = test_foreign_owner,
) -> HoverAnchor {
  HoverForeignElementAnchor(
    priority=10,
    owner~,
    injected_text_index~,
    range=Range(1, 5, 1, 5),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
    supports_marker_hover~,
  )
}

///|
test "anchor equals: range anchors compare ranges, foreign anchors compare owners only" {
  assert_true(hover_anchor_equals(range_anchor(1, 4, 4), range_anchor(1, 4, 4)))
  assert_false(
    hover_anchor_equals(range_anchor(1, 4, 4), range_anchor(1, 5, 5)),
  )
  assert_false(hover_anchor_equals(range_anchor(1, 4, 4), foreign_anchor(0)))
  // Payload/range do not participate when the explicit owner is the same.
  assert_true(hover_anchor_equals(foreign_anchor(0), foreign_anchor(3)))
  let other_owner = HoverParticipantOwner()
  assert_false(
    hover_anchor_equals(foreign_anchor(0), foreign_anchor(0, owner=other_owner)),
  )
  assert_false(hover_anchor_equals(foreign_anchor(0), range_anchor(1, 4, 4)))
}

///|
test "range and foreign anchor constructors retain every source field" {
  let range : HoverAnchor = HoverRangeAnchor(
    priority=4,
    range=Range(2, 3, 2, 5),
    initial_mouse_pos_x=Some(12.0),
    initial_mouse_pos_y=Some(18.0),
  )
  match range {
    HoverRangeAnchor(
      priority~,
      range=stored_range,
      initial_mouse_pos_x~,
      initial_mouse_pos_y~
    ) => {
      assert_eq(priority, 4)
      assert_true(stored_range == Range(2, 3, 2, 5))
      assert_true(initial_mouse_pos_x == Some(12.0))
      assert_true(initial_mouse_pos_y == Some(18.0))
    }
    _ => fail("expected range anchor")
  }

  let owner = HoverParticipantOwner()
  let foreign : HoverAnchor = HoverForeignElementAnchor(
    priority=10,
    owner~,
    injected_text_index=7,
    range=Range(3, 6, 3, 6),
    initial_mouse_pos_x=Some(20.0),
    initial_mouse_pos_y=Some(24.0),
    supports_marker_hover=true,
  )
  match foreign {
    HoverForeignElementAnchor(
      priority~,
      owner=stored_owner,
      injected_text_index~,
      range=stored_range,
      initial_mouse_pos_x~,
      initial_mouse_pos_y~,
      supports_marker_hover~
    ) => {
      assert_eq(priority, 10)
      assert_true(stored_owner == owner)
      assert_eq(injected_text_index, 7)
      assert_true(stored_range == Range(3, 6, 3, 6))
      assert_true(initial_mouse_pos_x == Some(20.0))
      assert_true(initial_mouse_pos_y == Some(24.0))
      assert_true(supports_marker_hover)
    }
    _ => fail("expected foreign anchor")
  }
}

///|
test "range adoption uses shown position while foreign adoption ignores it" {
  let old_range = range_anchor(1, 4, 4)
  let new_range = range_anchor(2, 9, 9)
  assert_true(hover_anchor_can_adopt_at(new_range, old_range, Position(2, 1)))
  assert_false(hover_anchor_can_adopt_at(new_range, old_range, Position(1, 9)))
  let foreign = foreign_anchor(0)
  assert_true(
    hover_anchor_can_adopt_at(foreign_anchor(3), foreign, Position(99, 1)),
  )
  assert_false(
    hover_anchor_can_adopt_at(
      foreign_anchor(3, owner=HoverParticipantOwner()),
      foreign,
      Position(1, 1),
    ),
  )
}

///|
test "hover parts are valid only for range anchors that their columns contain" {
  let part = MarkdownHover(
    range=Range(1, 4, 1, 8),
    contents=[PlainText("x")],
    ordinal=100,
  )
  assert_true(hover_part_valid_for_anchor(part, range_anchor(1, 5, 5)))
  assert_false(hover_part_valid_for_anchor(part, range_anchor(1, 9, 9)))
  // A foreign anchor invalidates range parts (`anchor.type === Range` gate).
  assert_false(hover_part_valid_for_anchor(part, foreign_anchor(0)))
}
