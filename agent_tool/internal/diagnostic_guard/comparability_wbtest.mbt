///|
fn site(path : String, loc : String, message : String) -> @auto_check.ErrorSite {
  { path: Some(path), loc, code: None, message, }
}

///|
fn check_result(
  errors : Array[@auto_check.ErrorSite],
  truncated? : Bool = false,
) -> @auto_check.CheckErrors {
  {
    error_count: errors.length(),
    warning_count: 0,
    errors,
    warnings: [],
    truncated,
  }
}

///|
fn target(path : String) -> EditedTarget {
  {
    spellings: [path],
    canonical: path,
    attributable: if moon_compiles(path) {
      [path]
    } else {
      []
    },
  }
}

///|
/// A project at `/r` with packages `x`, `y` (imports `x`), `z` (independent),
/// `w` (imports `z`), and `q` (imports `x` via a test import).
fn sample_graph() -> @auto_check.PackageGraph {
  {
    dirs: [Some("/r/x"), Some("/r/y"), Some("/r/z"), Some("/r/w"), Some("/r/q")],
    edges: [(1, 0), (3, 2), (4, 0)],
  }
}

///|
fn classify(
  before : @auto_check.CheckErrors?,
  after : @auto_check.CheckErrors,
  edited : Array[String],
) -> Comparability {
  comparability(
    before,
    after,
    edited.map(target),
    cwd=Some("/r"),
    graph=Some(sample_graph()),
  )
}

///|
/// The issue-#1452 shape: the pre-batch run stopped at 10 errors in the edited
/// package `x`; the batch fixed all 10, moon then compiled `y` (which imports
/// `x`), and 87 errors in `y` surfaced. By count that is "77 introduced"; by
/// the graph it is a reach through a dependent of the fixed package — real
/// but not certifiable, so the advice names the sites to vet and the value.
test "comparability calls new errors in dependents of a fixed package a plausible reach" {
  let before = check_result(
    [
      for index in 0..<10 => {
        site("x/x.mbt", "\{index + 1}:1-1:2", "wanted String")
      }
    ],
  )
  let after = check_result(
    [
      for index in 0..<87 => {
        site("y/y.mbt", "\{index + 1}:1-1:2", "wanted String")
      }
    ],
  )
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.remaining, 0)
  assert_eq(evidence.new_in_dependents.length(), 87)
  assert_true(evidence.verdict() is PlausibleReach)
  let advice = comparability_advice(evidence, introduced=77)
  assert_true(advice.contains("all 10 pre-batch error(s) are gone"))
  assert_true(advice.contains("depend on a package this batch FIXED"))
  assert_true(advice.contains("y/y.mbt:1:1-1:2: wanted String"))
  assert_true(advice.contains("… 82 more"))
  assert_true(advice.contains("Verify those sites"))
  assert_true(
    advice.contains(
      "If so: Re-issue the batch UNCHANGED with revert_if_error_delta_greater_or_equal=78",
    ),
  )
  assert_false(advice.contains("more precise old_strings"))
}

///|
test "comparability certifies new errors in packages independent of the edit" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  // `z` and `w` import nothing edited; moon reports absolute paths here.
  let after = check_result([
    site("/r/z/z.mbt", "3:1-3:2", "e1"),
    site("/r/w/w.mbt", "4:1-4:2", "e2"),
  ])
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.new_independent, 2)
  assert_true(evidence.verdict() is CertifiedReach)
  let advice = comparability_advice(evidence, introduced=1)
  assert_true(
    advice.contains("none of the 2 new error(s) can be caused by this batch"),
  )
  assert_true(
    advice.contains(
      "Re-issue the batch UNCHANGED with revert_if_error_delta_greater_or_equal=2",
    ),
  )
  assert_false(advice.contains("Verify those sites"))
}

///|
/// Review finding #3: a batch that fixes most but not all of the errors moon
/// stopped at must not be told to narrow itself when nothing points at it.
test "comparability keeps a partial fix on the reach path" {
  let before = check_result(
    [
      for index in 0..<10 => site("x/x.mbt", "\{index + 1}:1-1:2", "old")
    ],
  )
  let after = check_result(
    [
      ..[
        for index in 0..<4 => site("x/x.mbt", "\{index + 1}:1-1:2", "old")
      ],
      site("z/z.mbt", "1:1-1:2", "surfaced"),
    ],
  )
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.remaining, 4)
  assert_true(evidence.verdict() is CertifiedReach)
  let advice = comparability_advice(evidence, introduced=1)
  assert_true(
    advice.contains(
      "4 of 10 pre-batch error(s) remain (the batch fixed the rest)",
    ),
  )
  assert_false(advice.contains("more precise old_strings"))
}

///|
test "comparability calls a break in code that compiled before the batch breakage" {
  // `x` had no pre-batch errors (the only one was in `z`, and it remains); a
  // new error in `y`, which imports `x`, can only be the batch's doing. So can
  // one in another file of `x` itself.
  let before = check_result([site("z/z.mbt", "1:1-1:2", "unrelated")])
  let after = check_result([
    site("z/z.mbt", "1:1-1:2", "unrelated"),
    site("y/y.mbt", "7:1-7:2", "caller broke"),
    site("x/other.mbt", "2:1-2:2", "sibling broke"),
    site("q/q_test.mbt", "5:1-5:2", "test import broke"),
  ])
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.remaining, 1)
  assert_eq(evidence.new_breaking, [
    "y/y.mbt:7:1-7:2: caller broke", "x/other.mbt:2:1-2:2: sibling broke", "q/q_test.mbt:5:1-5:2: test import broke",
  ])
  assert_true(evidence.verdict() is Breakage)
  let advice = comparability_advice(evidence, introduced=3)
  assert_true(advice.contains("compiled cleanly before this batch"))
  assert_true(
    advice.contains(
      "fix the batch rather than raising revert_if_error_delta_greater_or_equal",
    ),
  )
  assert_false(advice.contains("UNCHANGED"))
}

///|
/// An edited symlink whose target lives in another package changes that
/// package too: `a/alias.mbt -> z/z.mbt` makes `w` (imports `z`) a dependent
/// of the edit, so a new error there is breakage when `z` was clean before.
test "comparability attributes through an edited symlink's target package" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  let after = check_result([site("w/w.mbt", "2:1-2:2", "caller broke")])
  let link : EditedTarget = {
    spellings: ["/r/x/alias.mbt", "/r/z/z.mbt"],
    canonical: "/r/x/alias.mbt",
    attributable: ["/r/x/alias.mbt", "/r/z/z.mbt"],
  }
  let evidence = comparability(
    Some(before),
    after,
    [link],
    cwd=Some("/r"),
    graph=Some(sample_graph()),
  )
  assert_eq(evidence.new_breaking, ["w/w.mbt:2:1-2:2: caller broke"])
  assert_true(evidence.verdict() is Breakage)
  // A target moon does not compile changes nothing in its package: the same
  // link resolving to `z/source.txt` leaves `w` independent of the edit.
  let data_link : EditedTarget = {
    spellings: ["/r/x/alias.mbt", "/r/z/source.txt"],
    canonical: "/r/x/alias.mbt",
    attributable: ["/r/x/alias.mbt"],
  }
  let surfaced = comparability(
    Some(before),
    check_result([site("w/w.mbt", "2:1-2:2", "surfaced")]),
    [data_link],
    cwd=Some("/r"),
    graph=Some(sample_graph()),
  )
  assert_eq(surfaced.new_breaking, [])
  assert_true(surfaced.verdict() is CertifiedReach)
  // …unless that target feeds a pre-build rule in `z` (then `edited_targets`
  // lists it as attributable), in which case `z` is edited after all.
  let build_input_link : EditedTarget = {
    ..data_link,
    attributable: ["/r/x/alias.mbt", "/r/z/source.txt"],
  }
  let generated = comparability(
    Some(before),
    check_result([site("w/w.mbt", "2:1-2:2", "caller broke")]),
    [build_input_link],
    cwd=Some("/r"),
    graph=Some(sample_graph()),
  )
  assert_true(generated.verdict() is Breakage)
  // A non-source file in the batch (a README) neither maps nor counts as
  // unmapped.
  let with_readme = classify(Some(before), check_result([]), [
    "/r/x/x.mbt", "/r/x/README.md",
  ])
  assert_eq(with_readme.unmapped_edits, 0)
}

///|
/// A fixed package's own test file: its blackbox tests could not compile
/// while the package was broken, so their errors surfacing is a plausible
/// reach, not proven breakage.
test "comparability keeps a fixed package's other files on the plausible path" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  let after = check_result(
    [
      for index in 0..<12 => {
        site("x/x_test.mbt", "\{index + 1}:1-1:2", "surfaced")
      }
    ],
  )
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.new_breaking, [])
  assert_eq(evidence.new_in_dependents.length(), 12)
  assert_true(evidence.verdict() is PlausibleReach)
  assert_true(
    comparability_advice(evidence, introduced=11).contains(
      "If so: Re-issue the batch UNCHANGED with revert_if_error_delta_greater_or_equal=12",
    ),
  )
}

///|
test "comparability treats new errors inside edited files as an over-match first" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  let after = check_result([
    site("x/x.mbt", "7:1-7:2", "stray"),
    site("x/x.mbt", "9:1-9:2", "stray"),
    site("z/z.mbt", "2:1-2:2", "independent"),
  ])
  let evidence = classify(Some(before), after, ["/r/x/x.mbt"])
  assert_eq(evidence.new_in_edited, [
    "x/x.mbt:7:1-7:2: stray", "x/x.mbt:9:1-9:2: stray",
  ])
  assert_eq(evidence.new_independent, 1)
  assert_true(evidence.verdict() is OverMatch)
  let advice = comparability_advice(evidence, introduced=3)
  assert_true(advice.contains("2 new error(s) sit in files this batch edited"))
  assert_true(advice.contains("x/x.mbt:9:1-9:2: stray"))
  assert_true(advice.contains("more precise old_strings"))
  assert_false(advice.contains("UNCHANGED"))
}

///|
/// Review finding #2: a check that ran in a project the batch did not edit
/// can never see the edited files, so its silence about them proves nothing.
test "comparability never claims reach when an edited file is outside the checked project" {
  let before = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  let after = check_result([site("z/z.mbt", "2:1-2:2", "surfaced")])
  let evidence = classify(Some(before), after, [
    "/r/x/x.mbt", "/elsewhere/scripts/tool.mbt",
  ])
  assert_eq(evidence.unmapped_edits, 1)
  assert_true(evidence.verdict() is Inconclusive(_))
  let advice = comparability_advice(evidence, introduced=1)
  assert_true(
    advice.contains(
      "1 edited file(s) lie outside every package of the checked project",
    ),
  )
  assert_false(advice.contains("UNCHANGED"))
}

///|
test "comparability is inconclusive without a baseline, a graph, or complete output" {
  let elsewhere = check_result([site("z/z.mbt", "1:1-1:2", "surfaced")])
  let old = check_result([site("x/x.mbt", "1:1-1:2", "old")])
  // Clean tree: it compiled everything, so the new errors are the batch's.
  assert_true(clean_tree_evidence().verdict() is Inconclusive(_))
  assert_true(
    comparability_advice(clean_tree_evidence(), introduced=1).contains(
      "checked clean before this batch",
    ),
  )
  // No baseline run at all.
  let missing = classify(None, elsewhere, ["/r/x/x.mbt"])
  assert_eq(missing.before_count, None)
  assert_true(
    comparability_advice(missing, introduced=1).contains(
      "pre-batch check could not run",
    ),
  )
  // Same shape as a reach, but the identity sets are partial.
  let truncated = classify(
    Some(check_result([site("x/x.mbt", "1:1-1:2", "old")], truncated=true)),
    elsewhere,
    ["/r/x/x.mbt"],
  )
  assert_true(truncated.truncated)
  assert_true(
    comparability_advice(truncated, introduced=1).contains(
      "error identities are incomplete",
    ),
  )
  // No package graph: nothing outside the edited files can be attributed.
  let no_graph = comparability(
    Some(old),
    elsewhere,
    [target("/r/x/x.mbt")],
    cwd=Some("/r"),
    graph=None,
  )
  assert_false(no_graph.graph_available)
  assert_true(
    comparability_advice(no_graph, introduced=1).contains(
      "could not report the package graph",
    ),
  )
  // A module manifest edit can change what every package sees.
  let manifest = classify(Some(old), elsewhere, ["/r/x/x.mbt", "/r/moon.mod"])
  assert_true(manifest.module_manifest_edited)
  assert_true(
    comparability_advice(manifest, introduced=1).contains(
      "edits a module manifest",
    ),
  )
  // A new error moon reported without a path, or in no known package, cannot
  // be placed, so it blocks the reach conclusion rather than counting as
  // "elsewhere".
  let nowhere = check_result([
    { path: None, loc: "2:1-2:2", code: None, message: "nowhere", },
    site("/outside/o.mbt", "1:1-1:2", "unknown package"),
  ])
  let unlocated = classify(Some(old), nowhere, ["/r/x/x.mbt"])
  assert_eq(unlocated.unlocated, 2)
  assert_true(
    comparability_advice(unlocated, introduced=2).contains(
      "2 new error(s) could not be placed in any package",
    ),
  )
}

///|
test "comparability compares by error code so a reworded message is not new" {
  let coded = fn(message : String) -> @auto_check.ErrorSite {
    { path: Some("x/x.mbt"), loc: "1:1-1:2", code: Some(4014), message, }
  }
  let evidence = classify(
    Some(check_result([coded("old wording")])),
    check_result([coded("new wording")]),
    ["/r/x/x.mbt"],
  )
  assert_eq(evidence.remaining, 1)
  assert_eq(evidence.new_in_edited, [])
}

///|
test "moon_compiles recognises sources and every manifest flavour" {
  assert_true(moon_compiles("/r/x/x.mbt"))
  assert_true(moon_compiles("/r/x/README.mbt.md"))
  assert_true(moon_compiles("/r/x/moon.pkg"))
  assert_true(moon_compiles("/r/x/moon.pkg.json"))
  assert_true(moon_compiles("/r/moon.mod"))
  assert_true(moon_compiles("/r/moon.mod.json"))
  assert_true(moon_compiles("/r/moon.work"))
  assert_false(moon_compiles("/r/x/README.md"))
  assert_false(moon_compiles("/r/x/source.txt"))
}

///|
test "absolutize joins moon's relative paths onto the checked project" {
  assert_eq(absolutize("x/x.mbt", Some("/r")), "/r/x/x.mbt")
  assert_eq(absolutize("/private/r/x.mbt", Some("/r")), "/private/r/x.mbt")
  assert_eq(absolutize("C:\\r\\x.mbt", Some("/r")), "C:\\r\\x.mbt")
  assert_eq(absolutize("x/x.mbt", None), "x/x.mbt")
}

///|
test "in_edited_file matches moon's relative paths against a target's spellings" {
  let spellings = ["/ws/cmd/openseek/main.mbt", "C:\\ws\\lib\\win.mbt"]
  assert_true(in_edited_file("cmd/openseek/main.mbt", spellings))
  assert_true(in_edited_file("/ws/cmd/openseek/main.mbt", spellings))
  assert_true(in_edited_file("win.mbt", spellings))
  // A same-named file in another directory is not the edited one.
  assert_false(in_edited_file("other/main.mbt", spellings))
  assert_false(
    in_edited_file("openseek/main.mbt", ["/ws/cmd/xopenseek/main.mbt"]),
  )
}

///|
fn clean_tree_evidence() -> Comparability {
  classify(
    Some(check_result([])),
    check_result([site("z/z.mbt", "1:1-1:2", "e")]),
    ["/r/x/x.mbt"],
  )
}

///|
test "inclusive retry threshold can exceed 200" {
  let evidence = classify(
    Some(check_result([site("x/x.mbt", "1:1-1:2", "old")])),
    check_result([site("z/z.mbt", "1:1-1:2", "new")]),
    ["/r/x/x.mbt"],
  )
  assert_true(
    evidence.feedback(delta=250).get("reissue_with") is Some(Number(251, ..)),
  )
  assert_true(reissue_advice(250).contains("greater_or_equal=251"))
}
