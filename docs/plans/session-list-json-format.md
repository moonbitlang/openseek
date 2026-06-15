# Session List JSON Format

## Goal

Split the machine-readable session listing needed by desktop into its own
preparatory CLI PR.

## Accepted Design

Add `--format` to `--session-list`, defaulting to the existing text output.
`--format=json` prints one JSON array containing session entries ordered like
the text listing.

Each JSON entry has:

- `id`: durable session id
- `title`: first line of the first user prompt, trimmed and truncated
- `updated_at_ms`: last activity timestamp in milliseconds, or `null` for
  unreadable session husks

## Target Files And Surfaces

- `cmd/openseek/main.mbt`
- `cmd/openseek/README.md`
- `tests/cram/cli.md`

## API / Interface Diff

New CLI option: `--format <text|json>`, currently meaningful for
`--session-list`.

No MoonBit package public API is intended to change.

## Open Questions

None for this PR. A future desktop protocol can replace this CLI JSON path with
a stdio query API.

## Next Implementation Step

Commit the extracted CLI JSON listing support and open it as a PR stacked on
the Windows global skills directory PR.

## Validation Plan

- `moon test cmd/openseek`
- `moon cram test tests/cram`
- `moon check`
- `moon info`
- `moon fmt`
