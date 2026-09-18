# UI localization

## Design

`desktop/frontend/i18n` owns pure locale selection and resolution. Features own
typed English/Simplified Chinese catalogs, with whole-sentence parameters and
exhaustive matches. Locale travels through reactive inputs, including keyed
conversation and transcript children. Language changes retain component state,
focus, queries and selected rows. Presentation language does not change command
IDs, paths, conversation content, code or provider output.

Settings offers System, English and 简体中文. System resolution follows the
ordered browser language list, respects explicit script tags and falls back to
English. Traditional Chinese is not treated as Simplified Chinese.

Browser preferences use localStorage. Native preferences use atomically replaced
`ui-language.json` in the host runtime directory, so temporary CEF profiles do
not reset the choice when the process exits. Missing preferences are optional;
read/write failures are reported without discarding the in-memory choice.

The editor owns an independent `viewer/common/localization` capability. Each
host supplies a language source through `ViewerServices`. Widgets bind label
updates to their lifecycle; the Desktop adapter maps its locale into the source.
The editor imports no Desktop settings or storage code.

## Implemented coverage

- Settings, provider/account/update controls, sidebar headings, project and
  conversation actions, archived chats and subagent counts.
- Quick Open, project picker, workspace settings, export dialogs, custom menus,
  Skills, scheduled task forms, job lists and workflow status.
- Composer, reasoning levels, attachments, approval controls, conversation
  chrome, timestamps, code-copy controls, tool summaries and notifications.
- Dock, terminal controls, browser toolbar, workspace search, file review and
  changes, dependency graph messages and hunk actions.
- Code/Markdown/diff accessibility labels, editor context menus, definition and
  reference navigation, hover controls, feedback and Markdown comment controls.
- Native menu labels and durable native language preference storage.

Product names, user-created titles, skills' original descriptions, model/tool
output, source code, paths and external diagnostics retain their source text.
OS-injected menu items such as Dictation follow the operating system language.

## Validation

- Root `just check`, offline `just test` and `just build` passed. The offline
  gate unsets DEEPSEEK, KIMI and GLM to avoid credential-gated live-provider
  tests: 3,222 native and 3,308 JavaScript tests passed, plus cram/integration
  gates. Subsequent label and optional-locale changes passed targeted frontend
  and Codex tests and the final root check.
- `just editor-test` passed: 1,100 Wasm, 1,891 JavaScript and 1,234 native tests.
  `just editor-test-browser` passed all 116 browser cases, including a new live
  localization test. Diff/Markdown-comment changes also passed 68 focused tests.
- All four Desktop localization browser cases passed: live page translation,
  saved preference/reload, system-language updates, Chinese IME, storage failure,
  and mounted editor language changes without reopening the file.
- Rebuilt the native app and selected Chinese through Settings. Checked sidebar,
  settings, Skills, scheduled task form, composer and native menus. Restarted
  the process and verified that Chinese was restored automatically.
- Native UI validation found that Proton's runtime menu replacement requires an
  explicit application menu label; the menu now supplies it. Chinese Edit menu
  actions and application restart were checked after the fix.
- `moon info` and `moon fmt` were run for both workspaces. Interface changes
  add optional locale/service inputs, explicit reactive locale inputs where
  needed, and native preference commands; editor host separation is preserved.

The editor's standalone asset-staging `.mbtx` commands now use the default Wasm
runner. This avoids an Apple Clang error in the standalone script's native async
dependency; application code and the native editor tests still build natively.

## Adding languages

See `desktop/frontend/i18n/README.mbt.md` for the Japanese extension checklist.
Add the locale, feature catalogs, editor mapping, native preference validation
and native menu labels. Exhaustive catalogs catch missing translations. Dynamic
Chinese/English branches must also become exhaustive locale matches when a
third language is introduced. This is modular, but not a single translation-file
import. Verify Japanese IME, date formatting, narrow layouts and persistence.
