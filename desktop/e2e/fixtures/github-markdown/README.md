# GitHub HTML fixtures

Recorded on 2026-09-22 with `POST /markdown`, `{ "mode": "gfm", "text": ... }`.
Each case stores its input and the unmodified GitHub API response. Browser
fixtures supply those responses directly as the protocol's `body_html`, as
returned from `bodyHTML` in production. Tests run offline and stub media bytes.
The Markdown inputs document fixture provenance and provide the chat raw-HTML
regression; they are not rendered locally for GitHub content.

`review-summary.md` reproduces the original reported screenshot's visible
summary, commit and fractional timestamp. The disclosure's complete boilerplate
comes from the same live [Codex comment template](https://github.com/moonbitlang/openseek/pull/1713#issuecomment-5770540925),
captured on 2026-09-22; the original comment may have been updated since the
screenshot. Its `.github.html` is an API response for this saved reproduction.

References: [GitHub's rendering pipeline](https://github.com/github/markup#github-markup)
and [relative-time-element](https://github.com/github/relative-time-element).
GitHub's API is an observation, not a versioned specification: review changes
when explicitly refreshing these fixtures with
`node desktop/e2e/fixtures/github-markdown/record.mjs`.

Tests assert native disclosure/time behavior, GitHub wrappers, attributes,
classes, highlighting and task checkboxes, original image proxy URLs and native
video playback. Only link hrefs are resolved against the source GitHub URL;
there is no DOM projection, Markdown equivalence or local HTML sanitization.

`clip.webm` is a two-second synthetic FFmpeg test pattern for offline playback:
`ffmpeg -f lavfi -i testsrc2=size=160x90:rate=10:duration=2 -c:v libvpx -b:v 80k -an clip.webm`.
