///|
test "an image-only Codex draft returns to OpenSeek and submits the same image" {
  let base = test_model()
  let empty : @composer.Draft = { task: "", mentions: [], images: [], }
  let (_, codex) = update(
    test_dispatch(),
    ComposerAction(
      @composer.ModelSelected(
        identity=base.composer_input().identity,
        value="codex:gpt-5.4-codex",
        draft=empty,
      ),
    ),
    base,
  )
  assert_true(codex.screen is Codex)
  let image_only : @composer.Draft = {
    task: "",
    mentions: [],
    images: [{ name: "screen.png", url: "data:image/png;base64,cGlj", }],
  }
  let (_, back) = update(
    test_dispatch(),
    CodexComposerAction(
      @composer.ModelSelected(
        identity=codex.codex_composer_input().identity,
        value="openseek:deepseek-v4-pro",
        draft=image_only,
      ),
    ),
    codex,
  )
  assert_true(back.screen is Chat)
  assert_true(back.composer_input().draft == image_only)
  assert_eq(back.active_session, base.active_session)
  assert_true(back.dev().sessions == base.dev().sessions)
  assert_false(back.codex.composing_draft())
  let (_, sent) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(
        identity=back.composer_input().identity,
        draft=image_only,
      ),
    ),
    back,
  )
  assert_true(sent.active().run is Starting(..))
  guard sent.active().pending_prompt is Some(pending) else {
    fail("missing image-only prompt")
  }
  assert_eq(pending.draft, "")
  assert_eq(pending.images, image_only.images)
  assert_true(pending.mentions.is_empty())
}
