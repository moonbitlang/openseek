// Tests for the registry's one-time setup. They redirect HOME, which decides
// both where the default workspace and the registry file land, so they take
// one lock rather than racing each other's environment.

///|
/// Mark the platform-gated wbtest alias as used: this binding is `_`-prefixed
/// (never warned about) and its body is never evaluated.
let _unused_wbtest_imports : Unit = ignore(@sys.get_env_var)
