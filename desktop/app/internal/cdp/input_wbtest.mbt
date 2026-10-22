///|
test "a click is a move, then a press and release of the primary button" {
  let at : Point = { x: 10.5, y: 20, }
  json_inspect(
    [
      ToJson::to_json(({ action: Move, at, } : MouseEvent)),
      ToJson::to_json(({ action: Press, at, } : MouseEvent)),
      ToJson::to_json(({ action: Release, at, } : MouseEvent)),
    ],
    content=[
      {
        "type": "mouseMoved",
        "x": 10.5,
        "y": 20,
        "button": "none",
        "buttons": 0,
        "clickCount": 0,
      },
      {
        "type": "mousePressed",
        "x": 10.5,
        "y": 20,
        "button": "left",
        "buttons": 1,
        "clickCount": 1,
      },
      {
        "type": "mouseReleased",
        "x": 10.5,
        "y": 20,
        "button": "left",
        "buttons": 0,
        "clickCount": 1,
      },
    ],
  )
}

///|
test "a key that types a character carries it down; one that does not goes down raw" {
  json_inspect(
    [
      ToJson::to_json(({ action: Down, key: Enter, } : KeyEvent)),
      ToJson::to_json(({ action: Up, key: Enter, } : KeyEvent)),
      ToJson::to_json(({ action: Down, key: Backspace, } : KeyEvent)),
      ToJson::to_json(({ action: Up, key: Backspace, } : KeyEvent)),
    ],
    content=[
      {
        "key": "Enter",
        "code": "Enter",
        "windowsVirtualKeyCode": 13,
        "type": "keyDown",
        "text": "\r",
      },
      {
        "key": "Enter",
        "code": "Enter",
        "windowsVirtualKeyCode": 13,
        "type": "keyUp",
      },
      {
        "key": "Backspace",
        "code": "Backspace",
        "windowsVirtualKeyCode": 8,
        "type": "rawKeyDown",
        "commands": ["deleteBackward"],
      },
      {
        "key": "Backspace",
        "code": "Backspace",
        "windowsVirtualKeyCode": 8,
        "type": "keyUp",
      },
    ],
  )
}

///|
test "content quads are four corners each" {
  assert_eq(decode_quads({ "quads": [[0, 0, 10, 0, 10, 5, 0, 5]] }), [
    [{ x: 0, y: 0, }, { x: 10, y: 0, }, { x: 10, y: 5, }, { x: 0, y: 5, }],
  ])
  assert_eq(decode_quads({ "quads": [] }), [])
  let rejected = try {
    ignore(decode_quads({ "quads": [[0, 0, 10, 0]] }))
    false
  } catch {
    Protocol(_) => true
    error => raise error
  }
  assert_true(rejected)
}
