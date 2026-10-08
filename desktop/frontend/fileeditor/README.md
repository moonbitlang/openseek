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
