///|
// Only event properties are needed to test shortcut selection without a DOM.
extern "js" fn settings_shortcut_event(
  key : String,
  code : String,
  shift : Bool,
  repeat : Bool,
  is_apple : Bool,
) -> @dom.KeyboardEvent =
  #| (key, code, shiftKey, repeat, isApple) => ({
  #|   key, code, shiftKey, repeat,
  #|   metaKey: isApple, ctrlKey: !isApple,
  #|   altKey: false, isComposing: false,
  #| })

///|
test "settings shortcut follows the period character across keyboard layouts" {
  for is_apple in [true, false] {
    // US period, a shifted period on another key, and a relocated period.
    for
      (code, shift) in [
        ("Period", false),
        ("Semicolon", true),
        ("Slash", false),
      ] {
      let event = settings_shortcut_event(".", code, shift, false, is_apple)
      assert_true(app_shortcut_message(event, is_apple) is Some(OpenSetup))
    }
  }
}

///|
test "settings shortcut ignores other characters and held-key repeats" {
  for is_apple in [true, false] {
    for
      (key, code, shift, repeat) in [
        (";", "Period", false, false),
        (">", "Period", true, false),
        (".", "Period", false, true),
        (".", "Semicolon", true, true),
      ] {
      let event = settings_shortcut_event(key, code, shift, repeat, is_apple)
      assert_true(app_shortcut_message(event, is_apple) is None)
    }
  }
}
