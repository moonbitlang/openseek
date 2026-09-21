///|
/// Agent-facing API-key resolution for the command mains that launch or resume
/// agent runs (`cmd/openseek`, the `openseek_tui` binary). This lived in `internal/agentcli`
/// because the resolution order was duplicated byte-for-byte across the mains,
/// and silent drift between the copies — one main learning a new provider
/// fallback and the other not — is the hazard the shared definition removes.
/// It sits on `Model` because the provider a key belongs to is exactly what
/// the model tag decides.
///
/// Only the resolution is shared. Returning an option leaves each main to
/// decide whether a missing key is fatal and to word its own diagnostic, so
/// the arms below are the single source of truth for *where* a key may come
/// from — `key_option` names the one variable this model may read — not for
/// what to say when there is none.

///|
/// The option (and, through the command table, the environment variable) that
/// carries this model's key.
///
/// A custom model follows its id's prefixes: `glm-*` and `kimi-*` keep the
/// provider whose wire names they resemble, and every other id travels in the
/// DeepSeek variable. The Desktop routes the same id to the same variable when
/// it spawns an engine (`key_env_for`), so the two rules must agree — this is
/// the engine's half of that one table.
fn Model::key_option(self : Model) -> String {
  match self {
    Deepseek(_) => "deepseek-api-key"
    Kimi(_) => "kimi-api-key"
    Glm(_) => "glm-api-key"
    Custom(id) =>
      if id.has_prefix("glm-") {
        "glm-api-key"
      } else if id.has_prefix("kimi-") {
        "kimi-api-key"
      } else {
        "deepseek-api-key"
      }
  }
}

///|
/// Resolve the API key for this model: an explicit `--api-key` wins, then the
/// provider-specific option (which each command table backs with the
/// provider's environment variable). `None` when neither is set — whether that
/// is fatal is the caller's call.
///
/// The option is chosen from the model (`key_option`), never guessed from
/// whatever the caller happened to set: only this model's own provider can
/// supply its key, and an unset, empty, or blank option simply yields `None`
/// rather than being defaulted to `""` and re-tested.
pub fn Model::api_key(
  self : Model,
  opts : Map[String, Array[String]],
) -> String? {
  // `trim` yields a borrowed view; the caller owns the key, so copy out.
  match opts {
    { "api-key": [k, ..], .. } if !k.is_blank() => Some(k.trim().to_owned())
    _ =>
      match opts.get(self.key_option()) {
        Some([k, ..]) if !k.is_blank() => Some(k.trim().to_owned())
        _ => None
      }
  }
}
