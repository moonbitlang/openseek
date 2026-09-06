// The decoration half of `vscode/src/vs/workbench/contrib/scm/browser/
// quickDiffDecorator.ts` (checked-in vscode submodule): `QuickDiffDecorator.
// createDecoration` and the change→decoration mapping of `onDidChange`.
//
// Structural deviation: the `EditorDecorationsCollection` this feeds is
// root-owned Viewer state. Its editor wiring (collection ownership, model /
// service listeners, and `QuickDiffWorkbenchController` editor tracking)
// therefore remains `Viewer::` glue in the root package
// (`viewer/quick_diff_host.mbt` / `viewer/quick_diff_contribution.mbt`).
// Keeping only the pure mapping here preserves the dependency direction from
// the root Viewer into this internal implementation package.
//
// Parity ledger (source members):
// - `QuickDiffDecorator.createDecoration` — PORTED REDUCED: gutter is the
//   only ported channel, so of the source's option channels
//   `linesDecorationsClassName` and `isWholeLine` remain;
//   `overviewRuler`/`minimap` — DEFERRED (neither view part is ported);
//   `linesDecorationsTooltip` — DEFERRED (`ModelDecorationOptions` has no
//   such field yet).
// - The ctor's option matrix — PORTED REDUCED to the three `primary`
//   non-pattern variants: `secondary` needs multiple providers (the service
//   stores one original per resource) and `pattern` needs the
//   `scm.diffDecorationsGutterPattern` setting (no configuration service);
//   both N-A. Config listeners — N-A likewise.
// - `onDidChange`'s change→decoration switch — PORTED as
//   `changes_to_decorations` (the provider-visibility and
//   primary-overlap filters are N-A under one provider).
// - `QuickDiffWorkbenchController` — N-A except for its stylesheet defaults
//   (gutter width 3, visibility `always`), which are baked into
//   `quick_diff.css`.

///|
/// `Number.MAX_VALUE` as a column sentinel (the marker system uses the same
/// convention, `viewer/common/markers`).
const MAX_COLUMN : Int = 0x7FFFFFFF

///|
/// `QuickDiffDecorator.createDecoration` (`quickDiffDecorator.ts:34`)
/// reduced to the gutter channel.
fn create_decoration(
  class_name : String,
  is_whole_line~ : Bool,
) -> @model.ModelDecorationOptions {
  ModelDecorationOptions(
    "",
    description="dirty-diff-decoration",
    is_whole_line~,
    lines_decorations_class_name="dirty-diff-glyph \{class_name}",
  )
}

///|
/// The ctor's `addedOptions` (`quickDiffDecorator.ts:94`).
let added_options : @model.ModelDecorationOptions = create_decoration(
  "dirty-diff-added primary",
  is_whole_line=true,
)

///|
/// The ctor's `modifiedOptions` (`quickDiffDecorator.ts:106`).
let modified_options : @model.ModelDecorationOptions = create_decoration(
  "dirty-diff-modified primary",
  is_whole_line=true,
)

///|
/// The ctor's `deletedOptions` (`quickDiffDecorator.ts:118`).
let deleted_options : @model.ModelDecorationOptions = create_decoration(
  "dirty-diff-deleted primary",
  is_whole_line=false,
)

///|
/// The change→decoration switch of `QuickDiffDecorator.onDidChange`
/// (`quickDiffDecorator.ts:140-194`): added/modified changes decorate their
/// modified line span whole-line, deletions pin a zero-width marker to the
/// end of the line the deleted block follows.
pub fn changes_to_decorations(
  changes : Array[@diff.DetailedLineRangeMapping],
) -> Array[@model.ModelDeltaDecoration] {
  changes.map(change => {
    let change_type = @quick_diff.get_change_type(change)
    match change_type {
      Delete => {
        let anchor_line_number = change.modified.start_line_number - 1
        {
          range: Range(
            anchor_line_number,
            MAX_COLUMN,
            anchor_line_number,
            MAX_COLUMN,
          ),
          options: deleted_options,
        }
      }
      Add | Modify => {
        let start_line_number = change.modified.start_line_number
        let end_line_number = change.modified.end_line_number_exclusive - 1
        {
          range: Range(start_line_number, 1, end_line_number, 1),
          options: if change_type is Add {
            added_options
          } else {
            modified_options
          },
        }
      }
    }
  })
}
