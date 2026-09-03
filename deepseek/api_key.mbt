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
/// from, not for what to say when there is none.

///|
/// Resolve the API key for this model: an explicit `--api-key` wins, then the
/// provider-specific option (which each command table backs with the
/// provider's environment variable). `None` when neither is set — whether that
/// is fatal is the caller's call.
///
/// Matching the model together with the parsed options makes the whole
/// resolution one ordered list of arms: the first arm to match is the key to
/// use, and only the arm for this model's provider can read that provider's
/// option. Returning an option is what keeps it that short — an unset, empty,
/// or blank option just fails to match and falls through, so no arm has to
/// default it to `""` and re-test that afterwards.
pub fn Model::api_key(
  self : Model,
  opts : Map[String, Array[String]],
) -> String? {
  // `trim` yields a borrowed view; the caller owns the key, so copy out.
  match (self, opts) {
    (_, { "api-key": [k, ..], .. }) if !k.is_blank() =>
      Some(k.trim().to_owned())
    (Deepseek(_), { "deepseek-api-key": [k, ..], .. }) if !k.is_blank() =>
      Some(k.trim().to_owned())
    (Kimi(_), { "kimi-api-key": [k, ..], .. }) if !k.is_blank() =>
      Some(k.trim().to_owned())
    (Glm(_), { "glm-api-key": [k, ..], .. }) if !k.is_blank() =>
      Some(k.trim().to_owned())
    _ => None
  }
}
