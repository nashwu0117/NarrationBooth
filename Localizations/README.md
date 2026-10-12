# Translations

NarrationBooth's interface is written in English and Traditional Chinese in the source code
(`T("繁體中文", "English")`). Every other language is one JSON file here that maps the English text to its translation:

```json
{
  "Open Script": "台本を開く",
  "Recorded %@ / %@": "録音済み %@ / %@"
}
```

| File | Language |
|---|---|
| `zh-Hans.json` | 简体中文 |
| `ja.json` | 日本語 |
| `ko.json` | 한국어 |
| `es.json` | Español |
| `fr.json` | Français |
| `de.json` | Deutsch |

## Fixing or adding a translation

- Keep placeholders exactly: `%@` (a value), `%.1f` / `%.0f` (numbers), `%%` (a percent sign). `%1$@ %2$@` can be
  reordered. Keep the leading space or line breaks a string starts with.
- Use the names macOS itself shows in your language for System Settings, Privacy & Security, Applications, etc.
- A missing or empty value falls back to English.
- Check your work with `python3 Scripts/check_translations.py`.

**A new language:** copy one of the files to `<code>.json` (an ISO 639-1 code such as `it`, or `pt-BR`), translate the
values, add the language to `UILanguage` in `Sources/NarrationBooth/L10n.swift`, and open a pull request.

When UI text changes, `python3 Scripts/check_translations.py --fix` adds the new English keys (empty) to every file.
