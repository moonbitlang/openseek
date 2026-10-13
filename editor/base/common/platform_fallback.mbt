///|
/// Non-js targets have no browser or Node environment to sniff; the platform
/// stays unknown. They exist only so the native check can enforce the
/// common tier's no-DOM boundary — nothing renders there.
fn detect_platform_code() -> Int32 {
  0
}
