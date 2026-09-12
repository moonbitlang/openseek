// White-box deterministic source-derived tests for
// `vscode/src/vs/editor/browser/config/fontMeasurements.ts` at vscode
// checked-in submodule.
// Multi-window, persistence, and disposal cases are intentionally absent owner
// seams; this file covers the approved single-window folded cache and complete
// request/measurement behavior.

///|
fn measurement_bare(
  family? : String = "Test Mono",
  features? : String = @common_config.editor_font_ligatures_off,
) -> @common_config.BareFontInfo {
  @common_config.BareFontInfo::create(
    font_family=family,
    font_weight="normal",
    font_size=12.0,
    font_feature_settings=features,
    font_variation_settings=@common_config.font_variation_off,
    line_height=18.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
}

///|
fn measure_with(
  width_for : (String, CharWidthRequestType) -> Double,
  features? : String = @common_config.editor_font_ligatures_off,
) -> @common_config.FontInfo {
  let measurements = new_font_measurements_for_test(
    (_bare, requests) => {
      for request in requests {
        request.fulfill(width_for(request.chr, request.request_type))
      }
    },
    () => 1.0,
    (_callback, _delay) => (),
  )
  measurements.read_font_info(measurement_bare(features~))
}

///|
fn trusted_font(family : String) -> @common_config.FontInfo {
  {
    ..@common_config.FontInfo::estimated(measurement_bare(family~)),
    is_trusted: true,
  }
}

///|
fn suspicious_axis_measurement(
  axis : Int,
  sample : Double,
) -> @common_config.FontInfo {
  measure_with((chr, _request_type) => {
    let is_digit = chr.length() == 1 && chr >= "0" && chr <= "9"
    let selected = match axis {
      0 => chr == "n"
      1 => chr == "\u{ff4d}"
      2 => chr == " "
      3 => chr == "·"
      4 => chr == "\u{2e31}"
      _ => is_digit
    }
    let trigger = if axis == 0 { chr == " " } else { chr == "n" }
    if selected {
      sample
    } else if trigger {
      2.0
    } else {
      10.0
    }
  })
}

///|
fn suspicious_axis_value(info : @common_config.FontInfo, axis : Int) -> Double {
  match axis {
    0 => info.typical_halfwidth_character_width
    1 => info.typical_fullwidth_character_width
    2 => info.space_width
    3 => info.middot_width
    4 => info.wsmiddot_width
    _ => info.max_digit_width
  }
}

///|
test "request corpus and style order match FontMeasurements" {
  let seen_chars : Array[String] = []
  let seen_types : Array[CharWidthRequestType] = []
  let measurements = new_font_measurements_for_test(
    (_bare, requests) => {
      for request in requests {
        seen_chars.push(request.chr)
        seen_types.push(request.request_type)
        // The three non-monospace requests deliberately differ. They must not
        // invalidate the monospace corpus itself.
        let width = if request.chr == "\u{ff4d}" || request.chr == "\u{2e31}" {
          20.0
        } else if request.chr == "￫" {
          9.0
        } else {
          10.0
        }
        request.fulfill(width)
      }
    },
    () => 2.0,
    (_callback, _delay) => (),
  )
  let info = measurements.read_font_info(measurement_bare())
  let expected = [
    "n", "\u{ff4d}", " ", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "→",
    "￫", "·", "\u{2e31}",
  ]
  let test_chars = ["|", "/", "-", "_", "i", "l", "m", "%"]
  for chr in test_chars {
    expected.push(chr)
    expected.push(chr)
    expected.push(chr)
  }
  assert_eq(seen_chars.length(), 41)
  assert_true(seen_chars == expected)
  for index in 0..<17 {
    assert_true(seen_types[index] == Regular)
  }
  for index in 17..<41 {
    let expected_type = match (index - 17) % 3 {
      0 => Regular
      1 => Italic
      _ => Bold
    }
    assert_true(seen_types[index] == expected_type)
  }
  assert_true(info.is_monospace)
  assert_eq(info.pixel_ratio, 2.0)
  assert_eq(info.typical_halfwidth_character_width, 10.0)
  assert_eq(info.typical_fullwidth_character_width, 20.0)
  assert_eq(info.space_width, 10.0)
  assert_eq(info.middot_width, 10.0)
  assert_eq(info.wsmiddot_width, 20.0)
  assert_eq(info.max_digit_width, 10.0)
  assert_eq(info.font_family, "Test Mono")
  assert_eq(info.font_weight, "normal")
  assert_eq(info.font_size, 12.0)
  assert_eq(
    info.font_feature_settings,
    @common_config.editor_font_ligatures_off,
  )
  assert_eq(info.font_variation_settings, @common_config.font_variation_off)
  assert_eq(info.line_height, 18)
  assert_eq(info.letter_spacing, 0.0)
  assert_true(info.is_trusted)
  // Halfwidth arrow is excluded from the mono corpus but has its own safety
  // equality gate against the reference width.
  assert_false(info.can_use_halfwidth_rightwards_arrow)
}

///|
test "every expected request has exact monospace subset membership" {
  let members : Array[(String, CharWidthRequestType)] = [
    ("n", Regular),
    (" ", Regular),
    ("→", Regular),
    ("·", Regular),
  ]
  for digit in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] {
    members.push((digit, Regular))
  }
  for chr in ["|", "/", "-", "_", "i", "l", "m", "%"] {
    members.push((chr, Regular))
    members.push((chr, Italic))
    members.push((chr, Bold))
  }
  for request_key in members {
    let info = measure_with((chr, request_type) => {
      if chr == request_key.0 && request_type == request_key.1 {
        10.01
      } else {
        10.0
      }
    })
    assert_false(info.is_monospace)
  }
  for
    excluded in [("\u{ff4d}", Regular), ("￫", Regular), ("\u{2e31}", Regular)] {
    let info = measure_with((chr, request_type) => {
      if chr == excluded.0 && request_type == excluded.1 {
        10.01
      } else {
        10.0
      }
    })
    assert_true(info.is_monospace)
  }
}

///|
test "max digit width considers each of the ten digit requests" {
  for widest in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] {
    let info = measure_with((chr, _request_type) => {
      if chr == widest {
        17.0
      } else {
        10.0
      }
    })
    assert_eq(info.max_digit_width, 17.0)
  }
}

///|
test "monospace tolerance is inclusive at plus and minus 0.001" {
  let at_plus = measure_with((chr, request_type) => {
    if chr == "|" && request_type == Italic {
      10.001
    } else {
      10.0
    }
  })
  let at_minus = measure_with((chr, request_type) => {
    if chr == "|" && request_type == Italic {
      9.999
    } else {
      10.0
    }
  })
  let outside_plus = measure_with((chr, request_type) => {
    if chr == "|" && request_type == Italic {
      10.0011
    } else {
      10.0
    }
  })
  let outside_minus = measure_with((chr, request_type) => {
    if chr == "|" && request_type == Italic {
      9.9989
    } else {
      10.0
    }
  })
  assert_true(at_plus.is_monospace)
  assert_true(at_minus.is_monospace)
  assert_false(outside_plus.is_monospace)
  assert_false(outside_minus.is_monospace)
  let ligatures_on = measure_with(
    (_chr, _request_type) => 10.0,
    features="normal",
  )
  assert_false(ligatures_on.is_monospace)
}

///|
test "halfwidth arrow gates distinguish mono equality and oversized glyphs" {
  let equal = measure_with((_chr, _request_type) => 10.0)
  assert_true(equal.can_use_halfwidth_rightwards_arrow)
  let mono_mismatch = measure_with((chr, _request_type) => {
    if chr == "￫" {
      9.0
    } else {
      10.0
    }
  })
  assert_false(mono_mismatch.can_use_halfwidth_rightwards_arrow)
  let proportional_safe = measure_with(
    (chr, _request_type) => if chr == "￫" { 9.0 } else { 10.0 },
    features="normal",
  )
  assert_true(proportional_safe.can_use_halfwidth_rightwards_arrow)
  let proportional_equal = measure_with(
    (_chr, _request_type) => 10.0,
    features="normal",
  )
  assert_true(proportional_equal.can_use_halfwidth_rightwards_arrow)
  let proportional_oversized = measure_with(
    (chr, _request_type) => if chr == "￫" { 11.0 } else { 10.0 },
    features="normal",
  )
  assert_false(proportional_oversized.can_use_halfwidth_rightwards_arrow)
  let mono_oversized = measure_with((chr, _request_type) => {
    if chr == "￫" {
      11.0
    } else {
      10.0
    }
  })
  assert_false(mono_oversized.can_use_halfwidth_rightwards_arrow)
}

///|
test "suspicious readings trigger at each owned boundary and floor all six widths" {
  // Each of the four trigger axes owns the same inclusive `<= 2` boundary.
  for axis in 0..<4 {
    for sample in [(1.999, false), (2.0, false), (2.001, true)] {
      let info = measure_with((chr, _request_type) => {
        let selected = match axis {
          0 => chr == "n"
          1 => chr == "\u{ff4d}"
          2 => chr == " "
          _ => chr.length() == 1 && chr >= "0" && chr <= "9"
        }
        if selected {
          sample.0
        } else {
          10.0
        }
      })
      assert_eq(info.is_trusted, sample.1)
    }
  }
  let half_trigger = measure_with((chr, _request_type) => {
    if chr == "n" {
      1.9
    } else {
      10.0
    }
  })
  let full_trigger = measure_with((chr, _request_type) => {
    if chr == "\u{ff4d}" {
      2.0
    } else {
      10.0
    }
  })
  let space_trigger = measure_with((chr, _request_type) => {
    if chr == " " {
      2.0
    } else {
      10.0
    }
  })
  let digit_trigger = measure_with((chr, _request_type) => {
    if chr.length() == 1 && chr >= "0" && chr <= "9" {
      2.0
    } else {
      10.0
    }
  })
  for info in [half_trigger, full_trigger, space_trigger, digit_trigger] {
    assert_false(info.is_trusted)
    assert_true(info.typical_halfwidth_character_width >= 5.0)
    assert_true(info.typical_fullwidth_character_width >= 5.0)
    assert_true(info.space_width >= 5.0)
    assert_true(info.middot_width >= 5.0)
    assert_true(info.wsmiddot_width >= 5.0)
    assert_true(info.max_digit_width >= 5.0)
  }
  let above = measure_with((chr, _request_type) => {
    if chr == "n" {
      2.001
    } else {
      10.0
    }
  })
  assert_true(above.is_trusted)
  let middot_only = measure_with((chr, _request_type) => {
    if chr == "·" {
      1.0
    } else {
      10.0
    }
  })
  assert_true(middot_only.is_trusted)
  assert_eq(middot_only.middot_width, 1.0)
  // The independently reused floor constant is exact for all six output
  // widths, at the below/equal/above boundary.
  for axis in 0..<6 {
    for pair in [(4.0, 5.0), (5.0, 5.0), (6.0, 6.0)] {
      let info = suspicious_axis_measurement(axis, pair.0)
      assert_eq(suspicious_axis_value(info, axis), pair.1)
    }
  }
}

///|
test "suspicious fallback rereads pixel ratio" {
  let reads = Ref(0)
  let measurements = new_font_measurements_for_test(
    (_bare, requests) => {
      for request in requests {
        request.fulfill(if request.chr == "n" { 2.0 } else { 10.0 })
      }
    },
    () => {
      reads.val += 1
      reads.val.to_double()
    },
    (_callback, _delay) => (),
  )
  let info = measurements.read_font_info(measurement_bare())
  assert_eq(reads.val, 2)
  assert_eq(info.pixel_ratio, 2.0)
  assert_false(info.is_trusted)
}

///|
test "cache hit, one pending retry, callback ordering, and conditional event" {
  let reads = Ref(0)
  let timers : Array[() -> Unit] = []
  let delays : Array[Int] = []
  let measurements = new_font_measurements_for_test(
    (_bare, requests) => {
      reads.val += 1
      for request in requests {
        request.fulfill(1.0)
      }
    },
    () => 1.0,
    (callback, delay) => {
      timers.push(callback)
      delays.push(delay)
    },
  )
  let a = measurement_bare(family="A")
  let b = measurement_bare(family="B")
  let c = measurement_bare(family="C")
  let first = measurements.read_font_info(a)
  let cached = measurements.read_font_info(a)
  assert_true(first == cached)
  assert_eq(reads.val, 1)
  measurements.read_font_info(b) |> ignore
  assert_eq(reads.val, 2)
  assert_eq(timers.length(), 1)
  assert_true(delays == [5000])
  let trusted = trusted_font("Trusted")
  measurements.write_to_cache(trusted.get_id(), trusted)
  let events = Ref(0)
  let listener = measurements.on_did_change(() => {
    events.val += 1
    // The source resets the pending sentinel before eviction and before this
    // event, so an untrusted read from the listener schedules a fresh retry.
    measurements.read_font_info(c) |> ignore
  })
  timers[0]()
  assert_eq(events.val, 1)
  assert_eq(timers.length(), 2)
  assert_true(measurements.evict_untrusted_readings_pending)
  assert_false(measurements.cache.contains(a.get_id()))
  assert_false(measurements.cache.contains(b.get_id()))
  assert_true(measurements.cache.contains(c.get_id()))
  assert_true(measurements.cache.contains(trusted.get_id()))
  listener.dispose()
}

///|
test "evicting an all-trusted cache is silent" {
  let mut scheduled = 0
  let measurements = new_font_measurements_for_test(
    (_bare, _requests) => (),
    () => 1.0,
    (_callback, _delay) => scheduled += 1,
  )
  let trusted = trusted_font("Trusted")
  measurements.write_to_cache(trusted.get_id(), trusted)
  // Trusted plus no pending retry is the missing false arm of the timer gate.
  assert_eq(scheduled, 0)
  let events = Ref(0)
  let listener = measurements.on_did_change(() => events.val += 1)
  measurements.evict_untrusted_readings()
  assert_eq(events.val, 0)
  assert_true(measurements.cache.contains(trusted.get_id()))
  listener.dispose()
}
