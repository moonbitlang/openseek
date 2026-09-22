///|
/// The verdict's name in `data`, one word per outcome.
fn Verdict::name(self : Verdict) -> String {
  match self {
    OverMatch => "over_match"
    Breakage => "breakage"
    Inconclusive(_) => "inconclusive"
    CertifiedReach => "certified_reach"
    PlausibleReach => "plausible_reach"
  }
}

///|
/// Evidence on whether the pre- and post-batch error counts are comparable.
///
/// `moon check` skips the dependents of a failing package, so a batch that
/// fixes the errors moon stopped at lets the build reach those dependents and
/// report errors that were always there; the count then rises without
/// breakage. A count delta cannot tell that from an over-match, but error
/// identities, locations and moon's package graph can, to a point:
///
/// - a new error INSIDE an edited file is an over-match;
/// - a new error in another file of an edited package that had NO pre-batch
///   errors, or in a package that depends on such a package, is breakage:
///   that code compiled cleanly before, so only the batch can have changed it;
/// - a new error in a package independent of everything edited cannot be
///   caused by the batch — certified reach;
/// - a new error in a package that depends on a package the batch FIXED is
///   ambiguous: moon had skipped that package, so the error may be pre-existing
///   or a caller broken by a changed signature; only the model can tell.
///
/// Every field is evidence; `verdict` turns them into one of five outcomes.
pub(all) struct Comparability {
  // The pre-batch run's error count; `None` when that run could not be made
  // (then every post-batch error was counted as introduced).
  before_count : Int?
  // Pre-batch errors (by `ErrorSite::identity`) still reported after.
  remaining : Int
  // New errors inside a file this batch wrote — the signature of an over-match.
  new_in_edited : Array[String]
  // New errors in code that compiled cleanly before and depends on (or shares
  // a package with) something this batch edited — caused by the batch.
  new_breaking : Array[String]
  // New errors in packages that depend on a package this batch fixed,
  // including that package's own other files: its tests and siblings were
  // not necessarily compiled while it was broken. Either surfacing or broken
  // by the fix.
  new_in_dependents : Array[String]
  // New errors in packages independent of everything edited — cannot be
  // caused by the batch.
  new_independent : Int
  // New errors that could not be placed: no path, or a path in no package
  // moon knows from the checked project.
  unlocated : Int
  // Edited files outside every package of the checked project: the check ran
  // somewhere the batch did not edit, so its silence about them proves nothing.
  unmapped_edits : Int
  // A `moon.mod`/`moon.work` edit can change what every package sees; the
  // package graph then says nothing about causation.
  module_manifest_edited : Bool
  // moon produced the package graph the classification above relies on.
  graph_available : Bool
  // Either run overflowed the capture budget, so the identity sets are
  // incomplete and no conclusion is drawn from them.
  truncated : Bool
}

///|
/// What the evidence adds up to, in precedence order: positive proof of
/// breakage first, then missing information, then the two reach outcomes.
priv enum Verdict {
  // New errors inside an edited file.
  OverMatch
  // New errors in code that compiled cleanly before and depends on the edit.
  Breakage
  // The comparison cannot be trusted either way; carries the reason.
  Inconclusive(String)
  // Every new error is in a package independent of the edit.
  CertifiedReach
  // Some new errors are in packages that depend on what the batch fixed.
  PlausibleReach
}

///|
/// Classify the collected evidence without changing the count-based decision.
fn Comparability::verdict(self : Comparability) -> Verdict {
  if !self.new_in_edited.is_empty() {
    return OverMatch
  }
  if !self.new_breaking.is_empty() {
    return Breakage
  }
  match self.before_count {
    None =>
      return Inconclusive(
        "the pre-batch check could not run, so every post-batch error was counted as introduced",
      )
    Some(0) =>
      return Inconclusive(
        "the tree checked clean before this batch, so every post-batch error is attributable to it",
      )
    Some(_) => ()
  }
  if self.truncated {
    return Inconclusive(
      "check output was truncated, so the error identities are incomplete",
    )
  }
  if !self.graph_available {
    return Inconclusive(
      "moon could not report the package graph, so new errors outside the edited files cannot be attributed",
    )
  }
  if self.module_manifest_edited {
    return Inconclusive(
      "the batch edits a module manifest (moon.mod/moon.work), which can change what every package sees",
    )
  }
  if self.unmapped_edits > 0 {
    return Inconclusive(
      "\{self.unmapped_edits} edited file(s) lie outside every package of the checked project, so the check never covered them",
    )
  }
  if self.unlocated > 0 {
    return Inconclusive(
      "\{self.unlocated} new error(s) could not be placed in any package",
    )
  }
  if self.new_in_dependents.is_empty() {
    CertifiedReach
  } else {
    PlausibleReach
  }
}

///|
/// A write target as moon might name it in a diagnostic. `spellings` are the
/// path as written, its directory canonicalized with the written name, and
/// the full realpath — moon reports the canonical directory (on macOS an edit
/// under `/tmp/…` is diagnosed under `/private/tmp/…`) but the file under the
/// name it compiled, so an edited `alias.mbt -> source.txt` is diagnosed as
/// `…/alias.mbt`. `canonical` is the spelling used to find the file's package.
priv struct EditedTarget {
  spellings : Array[String]
  canonical : String
  // The spellings whose package the edit can change: those moon compiles
  // (source and manifests) and those a pre-build rule in their package's
  // manifest names as an input. A README next to the sources is neither.
  attributable : Array[String]
}

///|
/// Resolve every write target's spellings. A path realpath cannot resolve
/// contributes what it can.
async fn edited_targets(paths : Array[String]) -> Array[EditedTarget] {
  let targets : Array[EditedTarget] = []
  for path in paths {
    let spellings : Array[String] = [path]
    let mut canonical = path
    if path.rev_split_once("/") is Some((dir, name)) && dir != "" {
      let canonical_dir = @fs.realpath(dir) catch { _ => dir.to_owned() }
      canonical = "\{canonical_dir}/\{name}"
      spellings.push(canonical)
    }
    let resolved : String? = Some(@fs.realpath(path)) catch { _ => None }
    if resolved is Some(resolved) {
      spellings.push(resolved)
    }
    let attributable : Array[String] = []
    for spelling in spellings {
      if moon_compiles(spelling) || is_build_input(spelling) {
        attributable.push(spelling)
      }
    }
    targets.push({ spellings, canonical, attributable, })
  }
  targets
}

///|
/// Whether a file moon does not compile can still change compiled code: a
/// `dev_build`/pre-build rule in its package's manifest names it as an input
/// (`moon check` runs those rules). Detected by the file's name appearing in
/// the manifest text — an over-match here only makes attribution more
/// conservative, never less.
async fn is_build_input(path : String) -> Bool {
  guard path.rev_split_once("/") is Some((dir, name)) && dir != "" else {
    return false
  }
  for manifest in ["moon.pkg", "moon.pkg.json"] {
    let text = @fs.read_file("\{dir}/\{manifest}").text() catch {
      _ => continue
    }
    if text.contains(name) {
      return true
    }
  }
  false
}

///|
/// Gather the evidence for a batch that breached the threshold: the project
/// moon checked from (`check_path`'s), its package graph, and the batch's
/// resolved targets, then classify.
pub async fn gather_comparability(
  check_path : String,
  before : @auto_check.CheckErrors?,
  after : @auto_check.CheckErrors,
  paths : Array[String],
) -> Comparability {
  let cwd = @auto_check.check_cwd(check_path)
  let graph = match cwd {
    Some(cwd) => @auto_check.package_graph(cwd) catch { _ => None }
    None => None
  }
  comparability(before, after, edited_targets(paths), cwd~, graph~)
}

///|
/// Pure classification of the two runs against the batch's targets. `cwd`
/// absolutizes moon's relative diagnostic paths; `graph` places paths in
/// packages and answers dependency questions.
fn comparability(
  before : @auto_check.CheckErrors?,
  after : @auto_check.CheckErrors,
  edited : Array[EditedTarget],
  cwd~ : String?,
  graph~ : @auto_check.PackageGraph?,
) -> Comparability {
  let seen : Set[String] = Set([])
  if before is Some(before) {
    for site in before.errors {
      seen.add(site.identity())
    }
  }
  let module_manifest_edited = edited.any(target => {
    let name = target.canonical.rev_after("/").unwrap_or(target.canonical)
    name == "moon.mod" || name == "moon.work"
  })
  // The packages this batch edited, and the subset that had pre-batch errors
  // (the ones the batch may have fixed, whose dependents moon skipped).
  let edited_pkgs : Array[Int] = []
  let mut unmapped_edits = 0
  if graph is Some(graph) {
    for target in edited {
      // Every spelling that moon would compile can name a package: a
      // symlink's own directory AND its target's — an edited
      // `a/alias.mbt -> z/z.mbt` changes package `z` too, so `z`'s dependents
      // must count as depending on the edit. A target moon does not compile
      // (`a/alias.mbt -> z/source.txt`) changes nothing in `z`. A target with
      // no compilable spelling at all (a README next to the sources) is
      // simply not part of the attribution.
      let compiled = target.attributable
      if compiled.is_empty() {
        continue
      }
      let mut mapped = false
      for spelling in compiled {
        guard graph.package_of(spelling) is Some(pkg) else { continue }
        mapped = true
        if !edited_pkgs.contains(pkg) {
          edited_pkgs.push(pkg)
        }
      }
      if !mapped {
        unmapped_edits += 1
      }
    }
  }
  let fixed_pkgs : Array[Int] = []
  if graph is Some(graph) && before is Some(before) {
    for site in before.errors {
      guard site.path is Some(path) else { continue }
      guard graph.package_of(absolutize(path, cwd)) is Some(pkg) else {
        continue
      }
      if edited_pkgs.contains(pkg) && !fixed_pkgs.contains(pkg) {
        fixed_pkgs.push(pkg)
      }
    }
  }
  let mut remaining = 0
  let mut unlocated = 0
  let mut new_independent = 0
  let new_in_edited : Array[String] = []
  let new_breaking : Array[String] = []
  let new_in_dependents : Array[String] = []
  for site in after.errors {
    if seen.contains(site.identity()) {
      remaining += 1
      continue
    }
    guard site.path is Some(path) else {
      unlocated += 1
      continue
    }
    let line = site.line()
    if edited.any(target => in_edited_file(path, target.spellings)) {
      new_in_edited.push(line)
      continue
    }
    guard graph is Some(graph) else { continue }
    guard graph.package_of(absolutize(path, cwd)) is Some(pkg) else {
      unlocated += 1
      continue
    }
    if edited_pkgs.contains(pkg) {
      // Another file of an edited package. If the package compiled cleanly
      // before, that file was compiled with the edit's file and a new error
      // here is the batch's doing. If the package was broken before, its
      // blackbox tests (a separate compilation unit that depends on it) and
      // possibly its siblings were skipped, so the error may be surfacing.
      if fixed_pkgs.contains(pkg) {
        new_in_dependents.push(line)
      } else {
        new_breaking.push(line)
      }
    } else if graph.depends_on(pkg, fixed_pkgs) {
      new_in_dependents.push(line)
    } else if graph.depends_on(pkg, edited_pkgs) {
      new_breaking.push(line)
    } else {
      new_independent += 1
    }
  }
  {
    before_count: before.map(b => b.error_count),
    remaining,
    new_in_edited,
    new_breaking,
    new_in_dependents,
    new_independent,
    unlocated,
    unmapped_edits,
    module_manifest_edited,
    graph_available: graph is Some(_),
    truncated: after.truncated || before.map(b => b.truncated).unwrap_or(false),
  }
}

///|
/// Whether moon compiles a file under this name: MoonBit source, a doc file
/// with checked fences, or a manifest that shapes a package or module.
fn moon_compiles(path : String) -> Bool {
  if path.has_suffix(".mbt") || path.has_suffix(".mbt.md") {
    return true
  }
  let name = path.rev_after("/").unwrap_or(path)
  name == "moon.pkg" ||
  name == "moon.pkg.json" ||
  name == "moon.mod" ||
  name == "moon.mod.json" ||
  name == "moon.work"
}

///|
/// moon reports diagnostic paths relative to the checked project or absolute;
/// make them absolute so they can be placed in a package.
fn absolutize(path : String, cwd : String?) -> String {
  let absolute = path.has_prefix("/") || (path.length() > 1 && path[1:2] == ":")
  match cwd {
    Some(cwd) if !absolute => "\{cwd}/\{path}"
    _ => path
  }
}

///|
/// Whether a diagnostic's path (as moon reported it: relative to the checked
/// project, or absolute and canonical) names one of a target's spellings.
fn in_edited_file(diagnostic_path : String, spellings : Array[String]) -> Bool {
  spellings.any(path => {
    path == diagnostic_path ||
    path.has_suffix("/\{diagnostic_path}") ||
    path.has_suffix("\\\{diagnostic_path}")
  })
}

///|
/// How many sites of one class the revert report lists by name.
const SiteDisplayLimit : Int = 5

///|
/// List up to `SiteDisplayLimit` sites of one class, with an overflow note.
fn site_list(sites : Array[String]) -> String {
  let limit = sites.length().min(SiteDisplayLimit)
  let shown = sites[:limit]
  let more = if sites.length() > shown.length() {
    "\n… \{sites.length() - shown.length()} more"
  } else {
    ""
  }
  "\n\{shown.join("\n")}\{more}"
}

///|
/// The inclusive threshold that admits the reported delta.
fn reissue_advice(introduced : Int) -> String {
  "Re-issue the batch UNCHANGED with revert_if_error_delta_greater_or_equal=\{introduced + 1}; it will then be kept and the remaining errors reported."
}

///|
/// Explain the verdict and, for reach cases, give the inclusive retry threshold.
pub fn comparability_advice(
  evidence : Comparability,
  introduced~ : Int,
) -> String {
  let narrow = "re-issue with more precise old_strings (include the receiver) and/or smaller batches so a replacement cannot stray onto unintended sites."
  let pre_batch = match evidence.before_count {
    Some(count) if evidence.remaining == 0 =>
      "all \{count} pre-batch error(s) are gone"
    Some(count) =>
      "\{evidence.remaining} of \{count} pre-batch error(s) remain (the batch fixed the rest)"
    None => "no pre-batch baseline"
  }
  match evidence.verdict() {
    OverMatch =>
      "comparability: \{pre_batch}; \{evidence.new_in_edited.length()} new error(s) sit in files this batch edited (over-match evidence):\{site_list(evidence.new_in_edited)}\n\{narrow}"
    Breakage =>
      "comparability: \{pre_batch}; \{evidence.new_breaking.length()} new error(s) are in code that compiled cleanly before this batch and depends on (or shares a package with) what it edited, so the batch caused them — a changed signature or type?\{site_list(evidence.new_breaking)}\nfix the batch rather than raising revert_if_error_delta_greater_or_equal."
    Inconclusive(reason) =>
      "comparability: \{pre_batch}; inconclusive — \{reason}. The count comparison cannot be trusted either way, so the batch stays reverted; \{narrow}"
    CertifiedReach =>
      "comparability: \{pre_batch}, and none of the \{evidence.new_independent} new error(s) can be caused by this batch: per moon's package graph they are in packages that depend on nothing it edited, and none is in an edited file. moon check skips the dependents of a failing package, so the pre-batch run stopped short of them and this delta is a measurement artifact, not breakage. \{reissue_advice(introduced)}"
    PlausibleReach =>
      "comparability: \{pre_batch}; no new error is in an edited file; \{evidence.new_independent} new error(s) are in packages independent of everything edited (cannot be caused by the batch); \{evidence.new_in_dependents.length()} are in packages that depend on a package this batch FIXED — moon had skipped those packages while their dependency was broken, so each is either a pre-existing error surfacing or a caller broken by a changed signature/type in the fix, and the tool cannot tell which:\{site_list(evidence.new_in_dependents)}\nVerify those sites are the pre-existing class you are fixing (not callers of something this batch changed). If so: \{reissue_advice(introduced)} If not, fix the batch."
  }
}
