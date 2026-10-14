///|
test "intersection excludes touching edges and maps independent axes" {
  let canvas : @selection.Rect = { x: 20, y: 40, width: 200, height: 100, }
  let requested : @selection.Rect = { x: 10, y: 60, width: 80, height: 150, }
  guard canvas.intersection(requested) is Some(crop) else {
    fail("missing crop")
  }
  assert_eq(crop, { x: 20, y: 60, width: 70, height: 80, })
  assert_eq(
    crop.mapped(from=canvas, to={ x: 0, y: 0, width: 400, height: 300, }),
    { x: 0, y: 60, width: 140, height: 240, },
  )
  assert_eq(
    canvas.intersection({ x: 220, y: 40, width: 10, height: 20, }),
    None,
  )
  assert_eq(
    canvas.intersection({ x: 20, y: 140, width: 10, height: 20, }),
    None,
  )
}

///|
test "viewport clipping, scroll translation and inclusive target edges" {
  let bounds : @selection.Rect = { x: -20, y: -30, width: 100, height: 100, }
  guard bounds.intersection({ x: 0, y: 0, width: 60, height: 60, })
    is Some(visible) else {
    fail("no viewport")
  }
  assert_eq(visible, { x: 0, y: 0, width: 60, height: 60, })
  assert_eq(visible.clamp_point({ x: -8, y: 80, }), { x: 0, y: 60, })
  assert_true(visible.contains({ x: 60, y: 30, }, inclusive=true))
  assert_true(!visible.contains({ x: 60, y: 30, }, inclusive=false))
  assert_eq(visible.translated({ x: 20, y: 130, }), {
    x: 20,
    y: 130,
    width: 60,
    height: 60,
  })
}

///|
test "drag threshold is radial, reversible and sticky" {
  let origin : @selection.Point = { x: 30, y: 40, }
  assert_eq(
    @selection.drag_rect(origin, { x: 32, y: 42, }, selecting=false),
    None,
  )
  assert_eq(
    @selection.drag_rect(origin, { x: 34, y: 40, }, selecting=false),
    Some({ x: 30, y: 40, width: 4, height: 0, }),
  )
  assert_eq(
    @selection.drag_rect(origin, { x: 27, y: 37, }, selecting=false),
    Some({ x: 27, y: 37, width: 3, height: 3, }),
  )
  assert_eq(
    @selection.drag_rect(origin, origin, selecting=true),
    Some({ x: 30, y: 40, width: 0, height: 0, }),
  )
}

///|
test "output uses highest density and enforces both allocation limits" {
  guard @selection.output_size({ x: 0, y: 0, width: 10.1, height: 5.1, }, [
      1, 2, 1.5,
    ])
    is Some(size) else {
    fail("no size")
  }
  assert_eq(size.scale, 2)
  assert_eq(size.width, 21)
  assert_eq(size.height, 11)
  assert_true(
    @selection.output_size({ x: 0, y: 0, width: 4096, height: 4096, }, [1])
    is Some(_),
  )
  assert_eq(
    @selection.output_size({ x: 0, y: 0, width: 4096, height: 4097, }, [1]),
    None,
  )
  assert_eq(
    @selection.output_size({ x: 0, y: 0, width: 16385, height: 1, }, [1]),
    None,
  )
  assert_eq(
    @selection.output_size({ x: 0, y: 0, width: 1, height: 16385, }, [1]),
    None,
  )
  assert_eq(
    @selection.output_size({ x: 0, y: 0, width: 10, height: 10, }, []),
    None,
  )
}

///|
test "PNG limit retains the conservative base64 boundary" {
  let prefix = "data:image/png;base64,"
  assert_true(@selection.png_within_limit(prefix + String::make(6990506, 'A')))
  assert_true(!@selection.png_within_limit(prefix + String::make(6990507, 'A')))
}

///|
test "bitmap placement composes parent rotation and child counter rotation" {
  let rotation : @selection.LinearTransform = { a: 0, b: 1, c: -1, d: 0, }
  let counter : @selection.LinearTransform = { a: 0, b: -1, c: 1, d: 0, }
  let placement = @selection.bitmap_placement(
    [{ linear: counter, opacity: 0.5, }, { linear: rotation, opacity: 0.8, }],
    { x: 40, y: 80, width: 30, height: 10, },
    { x: 30, y: 10, },
    { x: 60, y: 20, },
    { x: 20, y: 30, width: 200, height: 200, },
    2,
  )
  assert_eq(placement.linear, { a: 1, b: 0, c: 0, d: 1, })
  assert_eq(placement.origin, { x: 40, y: 100, })
  assert_eq(placement.opacity, 0.4)
}

///|
test "bitmap rotation and reflection recover the displayed origin" {
  let placement = @selection.bitmap_placement(
    [{ linear: { a: 0, b: 1, c: -1, d: 0, }, opacity: 1, }],
    { x: 40, y: 80, width: 10, height: 30, },
    { x: 30, y: 10, },
    { x: 60, y: 20, },
    { x: 20, y: 30, width: 200, height: 200, },
    2,
  )
  assert_eq(placement.linear, { a: 0, b: 1, c: -1, d: 0, })
  assert_eq(placement.origin, { x: 60, y: 100, })
  let mirrored = @selection.bitmap_placement(
    [{ linear: { a: -1, b: 0, c: 0, d: 1, }, opacity: 1, }],
    { x: 40, y: 80, width: 30, height: 10, },
    { x: 30, y: 10, },
    { x: 30, y: 10, },
    { x: 0, y: 0, width: 200, height: 200, },
    1,
  )
  assert_eq(mirrored.origin, { x: 70, y: 80, })
}
