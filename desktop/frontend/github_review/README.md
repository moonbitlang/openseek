# GitHub review conversations

The root `github.State` owns one current-PR lookup for the checkout, shared
by the GitHub panel and Review. Switching between them reuses pending or ready results;
reopening after leaving, changing host/directory/branch/HEAD, refreshing, or
completing checkout revalidates it. Review consumes that result to show the
comments toggle for open PRs, including drafts. Closed, merged and absent PRs
hide it; failed checks offer a retry. Enabling comments loads discussions.
Saved branch associations identify a PR, but GitHub still verifies its lifecycle.
Late responses cannot restore controls for a previous checkout or a closed PR.

Comments use the existing Line, Token and Tree comparisons and split/unified
preference. Narrow panels use unified layout while comments are enabled.
GitHub comments disable local agent feedback, including during requests;
turning the toggle off restores eligible feedback controls immediately.
The Changes tree counts unresolved conversations.

The host uses `gh api` with argument arrays and closed stdin. GraphQL reads
threads, permissions and all pages of replies; REST posts comments, replies
and deletions; GraphQL resolves conversations. Comment IDs remain decimal
strings across native and JS boundaries.

Discussions and local file snapshots use separate requests. File navigation
caches immutable Git contents by PR URL, merge base and head, without reloading
discussions. Refresh keeps verified anchors available and invalidates the cache
when the PR revision changes. Inline placement requires an exact match with the
displayed source pair. Local edits, missing commits, outdated anchors and hidden
sections leave conversations in an expandable list above the diff, where
reply, delete and resolve remain available.

New line comments use the positions in GitHub's paginated PR file patches,
loaded with the discussions and checked against the same base/head revisions.
LEFT targets are deleted lines; RIGHT targets are added or context lines, as
defined by the [GitHub review comment API](https://docs.github.com/en/rest/pulls/comments#create-a-review-comment-for-a-pull-request).
Missing sides remain optional in the file snapshot. Empty, binary, omitted
patches and lines outside the returned diff have no new-comment action;
existing conversations and local drafts remain available.

Drafts are keyed by PR URL. The native app saves them atomically in its local runtime directory, independently of temporary CEF profiles and remote workspace hosts; the browser client uses localStorage. Native reads, edits and post-send cleanup share an ordered lane so an older save cannot overwrite a newer edit. New comments record file, side,
line and head. Typing never creates a GitHub review; Send publishes immediately
and Cancel discards the draft. Failed or unconfirmed sends retain it. Storage
errors preserve unsaved text in the window. Earlier-head drafts require copying
to a current line, and the host rechecks the head before posting.

**Update checkout**, available in Review and on the current PR row, reuses the
uncommitted-change dialog. It updates the existing local branch with
`gh pr checkout --branch` without forcing a diverged branch. Success refreshes
the comparison, graph and comments even if HEAD is unchanged; updating from
Review keeps the selected file open. Refreshing comments is read-only.

## Reference scope and verification

This is a behavior port of VS Code GitHub Pull Requests at
`2f06150abfa874acf68db1c5528ad41a6ec23e20`, principally
`src/github/pullRequestModel.ts` and `src/github/queriesShared.gql`.
The editor owns generic line blocks and geometry; Desktop owns GitHub identity,
rendering, storage and commands. Cloud pending reviews, batch submission,
editing, reactions and suggestions are outside this feature.

Host tests cover CLI arguments, IDs, pagination, lifecycle and pinned Git
snapshots. Reducer tests cover ownership, caches and draft failure transitions.
Desktop browser scenarios cover mode switching, discussion actions, persistence
and checkout recovery with a replaced native transport. The editor's
`diff-line-widgets` scenario covers DOM ownership, paired geometry, focus,
resize, wheel routing and teardown. Browser tests do not publish to GitHub.
