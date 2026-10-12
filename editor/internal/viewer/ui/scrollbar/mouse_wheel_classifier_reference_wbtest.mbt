// Exact classifier checks over wheel-event traces copied from the pinned VS Code source.

///|
fn run_classifier_trace(
  trace : Array[Array[Double]],
  expected_physical : Bool,
  skip_first~ : Bool = false,
) -> Unit raise {
  let classifier = MouseWheelClassifier()
  assert_true(trace.length() > 0)
  for index, event in trace {
    classifier.accept(event[0], event[2], event[1])
    if !skip_first || index > 0 {
      assert_eq(classifier.is_physical_mouse_wheel(), expected_physical)
    }
  }
}

///|
test "upstream classifier trace: OSX - Apple Magic Mouse" {
  run_classifier_trace(classifier_trace_osx_apple_magic_mouse, false)
}

///|
test "upstream classifier trace: OSX - Apple Touch Pad" {
  run_classifier_trace(classifier_trace_osx_apple_touch_pad, false)
}

///|
test "upstream classifier trace: OSX - Razer Physical Mouse Wheel" {
  run_classifier_trace(classifier_trace_osx_razer_physical_mouse_wheel, true)
}

///|
test "upstream classifier trace: Windows - Microsoft Arc Touch" {
  run_classifier_trace(classifier_trace_windows_microsoft_arc_touch, true)
}

///|
test "upstream classifier trace: Windows - SurfaceBook TouchPad" {
  run_classifier_trace(classifier_trace_windows_surface_book_touch_pad, false)
}

///|
test "upstream classifier trace: Windows - Razer physical wheel" {
  run_classifier_trace(classifier_trace_windows_razer_physical_wheel, true)
}

///|
test "upstream classifier trace: Windows - Logitech physical wheel" {
  run_classifier_trace(classifier_trace_windows_logitech_physical_wheel, true)
}

///|
test "upstream classifier trace: Windows - Microsoft basic v2 physical wheel" {
  run_classifier_trace(
    classifier_trace_windows_microsoft_basic_v2_physical_wheel, true,
  )
}

///|
test "upstream classifier trace: Linux Wayland - Logitech G Pro Wireless" {
  run_classifier_trace(
    classifier_trace_linux_wayland_logitech_g_pro_wireless,
    true,
    skip_first=true,
  )
}
