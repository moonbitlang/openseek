// The path variable: its separator, and the two ways this app prepends a
// directory to it. Shared by the engine's child environments and the bundled
// MoonBit toolchain's, which spawn children the same way and must agree on
// the platform separator and on the Windows `Path`-vs-`PATH` rule.

///|
/// The platform's path-variable separator: `;` on Windows, `:` elsewhere.
///
/// A `pub let`, not a `pub const`. A public `#cfg` const bakes whichever value
/// survived into `pkg.generated.mbti`, so regenerating the interface on Windows
/// rewrites it and the committed one no longer matches. A `let` records only
/// `path_sep : String`, which is identical on every platform.
/// `ExecutableSuffix` in `internal/moonbit` has the same `#cfg` shape but is
/// private, so it never reaches an interface at all.
///
/// TODO(upstream): support `declare pub let`, so this note can sit on one
/// declaration instead of above the arms.
// declare pub let path_sep : String

///|
/// `;` on Windows — see the note above.
#cfg(platform="windows")
pub let path_sep : String = ";"

///|
/// `:` on non-Windows targets — see the note above.
#cfg(not(platform="windows"))
pub let path_sep : String = ":"

///|
/// `bin_dir` prepended to `current_path`, or `bin_dir` alone when there is no
/// path to extend.
pub fn prepend_to_path_env(bin_dir : String, current_path : String?) -> String {
  if current_path is Some(path) && !path.is_empty() {
    "\{bin_dir}\{path_sep}\{path}"
  } else {
    bin_dir
  }
}

///|
/// Prepend `bin_dir` to the environment block's path variable, in place, and
/// return the updated value. Windows blocks commonly spell the key `Path`
/// (and `@sys.get_env_vars` preserves that spelling); a block passed to a
/// child with `inherit_env=false` that carried a separate uppercase `PATH`
/// beside it would leave two path variables and make which one the child
/// observes a runtime coin toss. Update the spelling that already exists and
/// drop any duplicates.
pub fn prepend_path_entry(
  env : Map[String, String],
  bin_dir : String,
) -> String {
  let spellings = [
    for name in env.keys() if name.to_upper() == "PATH" => name
  ]
  for index, name in spellings {
    if index > 0 {
      env.remove(name)
    }
  }
  let key = spellings.get(0).unwrap_or("PATH")
  let joined = prepend_to_path_env(bin_dir, env.get(key))
  env[key] = joined
  joined
}
