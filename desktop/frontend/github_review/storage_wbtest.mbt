///|
extern "js" fn install_draft_bridge() -> () -> Unit =
  #| () => {
  #|   const previous = globalThis.__MoonBit__;
  #|   const saved = new Map();
  #|   let first = true;
  #|   globalThis.__MoonBit__ = { openseek: {
  #|     "github.drafts_get": async ({url}) => ({url, drafts: saved.get(url) || []}),
  #|     "github.drafts_set": async ({url, drafts}) => {
  #|       if (first) { first = false; await new Promise(resolve => setTimeout(resolve, 30)); }
  #|       saved.set(url, drafts);
  #|       return { ok: true };
  #|     },
  #|   }};
  #|   return () => { globalThis.__MoonBit__ = previous; };
  #| }

///|
async test "native draft writes stay ordered and sending cannot erase a newer edit" {
  let restore = install_draft_bridge()
  defer restore()
  let url = "https://github.example/o/r/pull/42"
  let old : GithubDraft = {
    target: Thread(thread="thread", comment="comment"),
    body: "older draft",
  }
  let newer = { ..old, body: "newer edit", }
  let pending = @js.Promise::from_async(() => store_drafts(url, [old]))
  assert_true(store_drafts(url, [newer]) is Ok(_))
  assert_true(pending.wait() is Ok(_))
  assert_true(load_drafts(url) is Ok([draft]) && draft == newer)
  assert_true(remove_sent_draft(url, old) is Ok(_))
  assert_true(load_drafts(url) is Ok([draft]) && draft == newer)
  assert_true(remove_sent_draft(url, newer) is Ok(_))
  assert_true(load_drafts(url) is Ok([]))
}
