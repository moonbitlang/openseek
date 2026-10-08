# File editor resource ownership

The imperative source host owns a bounded `SourceModelCache`, separate from
the dock's loaded raw text and its persisted view states. A cache scope is the
conversation owner plus exact checkout root; the resource key is the complete
model URI, including live/notice schemes. Normal source and rich Markdown
borrow through one active `SourceModelLease`. Detaching a surface releases the
lease rather than disposing the cached model, preserving lexical tokens when
an already-open tab returns.

The cache retains at most 12 entries and an estimated 8MiB of UTF16 text, line
projections and encoded tokens. Only unleased entries can be LRU-evicted.
Active borrowers can temporarily exceed that idle budget. Closing a tab retires
its live and notice entries; a retired model is disposed after its last lease.
Conversation/checkout changes retire the entire scope and clear view states.
An unchanged LF/CRLF/CR input does not flush; actual changed input updates the
resource model and its content version before attaching it. Dock read/review
generations remain the authority for accepting asynchronous host replies.

Immutable review pairs/fragments and provider-owned Peek previews retain their
existing separate model ownership. They cannot alias the live resource by
basename or accidentally inherit its writable-service identity. The generic
editor continues to borrow all models; product cache policy stays here.

Drag listeners store the newest requested size and publish CSS plus active
surface layout in one shared editor animation frame. Mouseup cancels a pending
frame and commits the final size. Source initialization finishes restore/fold,
synchronous geometry, reveal and stable lexical demand before its first paint.

Large code sources are prepared through `Viewer.prepare_model` before their
atomic show transaction. A preparation holds its own source lease and a
cancelable job. A new show, clear, conversation or checkout boundary cancels
that job and releases the lease. Large reloads detach before changing the cached
model, so the outgoing folding contribution cannot scan the new content inline.
The model/version/rules-specific structural folding cache never shares mutable
collapse flags; stored view states remain the authority for user fold choices.
A late or failed preparation cannot publish the previous file under a new tab.
The package ships the matching `editor-code-worker.js` beside `frontend.js`.

Semantic review sections may become ready before the whole-file Line worker.
Viewed hunk coverage remains partial while that complete universe is unknown.
When fresh file coverage arrives, the exact row/review/surface generation gates
run before merging it: a file becomes complete only if its stored viewed ranges
contain every changed range. Late coverage never marks an untouched file or
restores a hunk the user explicitly unviewed.
