// `explore_system_prompt()` — the read-only scout's system prompt — is
// generated from `explore_system_prompt.mbt.md` by the `md_to_mbt_string`
// dev_build rule (see moon.pkg). Edit the markdown, not the generated
// `.mbt`. The instrument hierarchy the prompt encodes is the point —
// MoonBit is young and model priors about its APIs are unreliable, so the
// prompt spells out where API truth actually lives.

///|
/// The child's task: the parent's question, plus optional hints about where
/// to look.
fn explore_task(
  query : String,
  hints : String?,
  scratch_dir : String?,
) -> String {
  let lab = match scratch_dir {
    Some(lab) =>
      (
        $|
        $|Your scratch lab (writable): \{lab}
        $|Create files and projects THERE and run any moon command there
        $|(moon new / check / test) to verify claims empirically — a 3-step
        $|experiment beats 30 steps of doc archaeology, and grepping
        $|binaries with `strings` is never the answer. The workspace itself
        $|stays read-only.
      )
    None => ""
  }
  match hints {
    Some(hints) =>
      (
        $|Question:
        $|\{query}
        $|
        $|The caller suggests starting from:
        $|\{hints}
        $|\{lab}
        $|Answer the question and submit_answer, with citations.
      )
    None =>
      (
        $|Question:
        $|\{query}
        $|\{lab}
        $|Answer the question and submit_answer, with citations.
      )
  }
}
