# UI locale

This package owns language selection and resolution, without browser state or
feature text. The application reads browser preferences and storage at its
boundary, then passes the resolved `Locale` into reactive component inputs.
Components keep their own typed message catalogs and render whole messages.

```mbt check
///|
test "resolve a persisted preference at the application boundary" {
  let preference = @i18n.Preference::parse("system").unwrap_or(@i18n.System)
  let locale = preference.resolve(["zh-Hans-CN", "en-US"])
  assert_eq(locale.tag(), "zh-Hans")
  assert_eq(preference.wire(), "system")
}
```

`Preference::parse` returns `None` for an unsupported stored value. A storage
read failure must be carried separately by the caller, not converted into an
absent value. System resolution chooses the first supported language in browser
preference order, then English. Traditional Chinese is not silently mapped to
Simplified Chinese; explicit script tags take precedence over region.

Changing locale must be a reactive input change, including for independently
rendered components. The locale must not change command IDs, protocol fields,
paths, conversation text or model output.

## Adding another language (for example Japanese)

1. Add `Japanese` to `Locale` and `Preference`, use the stable tag `ja`, and
   recognize `ja` / `ja-JP` in ordered system-language resolution. Extend the
   round-trip, fallback and language-order tests.
2. Add 日本語 to the Settings language picker and a Japanese arm for every
   feature-owned message enum in `desktop/frontend/**/messages.mbt` and other
   `*_messages.mbt` catalogs. Exhaustive matches identify missing catalog arms.
   Translate complete sentences, keeping interpolation parameters intact.
3. Audit dynamic formatting branches that currently test `SimplifiedChinese`.
   Move those into exhaustive locale matches as the third language is added;
   a boolean Chinese/English branch would otherwise silently display English.
4. Add Japanese to the independent editor language/catalog under
   `editor/viewer/common/localization`, then map it in Desktop's
   `fileeditor/localization.mbt`. Share a source through `ViewerServices` to
   update mounted editor controls without rebuilding document models.
5. Extend the native host's accepted preference values and native menu labels
   under `desktop/backend/internal/{host,extension}`. Browser preferences use
   localStorage; native preferences use the runtime directory's
   `ui-language.json`, independent of temporary browser profiles.
6. Verify live switching, Japanese IME, date formatting, narrow layouts,
   browser reload and native restart. Extend the existing localization browser
   tests; retain original paths, code, conversation titles and provider output.

No feature needs a separate Japanese implementation. Adding a third language
requires translations and these boundary mappings; it is not yet a single-file
translation import.
