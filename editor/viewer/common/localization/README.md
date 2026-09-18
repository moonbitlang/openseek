# Editor localization

`Localization` is a host-owned language source for editor controls. Pass one
source to `ViewerServices` to share a language across code, Markdown and diff
viewers, or create independent sources for independent embeds. The default is
English; Simplified Chinese and Japanese are also available. Document text,
provider diagnostics and custom command titles remain
owned by their producers.

`set_language` updates mounted labels. Widgets bind callbacks through `bind`,
which renders immediately and returns a disposable; dispose this binding with
the widget. The host owns the source lifetime. The editor does not import
Desktop settings or storage.

To add a language, extend `Language` and the exhaustive message catalog, audit
dynamic sentence formatting, then add the language mapping in each host. The
shell's language toggle and browser localization regression provide the fast
preview loop; Desktop adapts the same service in `fileeditor/localization.mbt`.
