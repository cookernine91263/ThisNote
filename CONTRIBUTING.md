# Contributing

Thanks for helping ThisNote stay quiet and dependable.

## Before you start

```powershell
cd app
flutter pub get
flutter analyze
flutter test
```

The app targets Windows and Android. UI text is Chinese-first; add English in the file's `_en` map.

## Principles

- Local-first: no account, no default upload, no telemetry.
- Keep the paper, ink and vermilion visual language. New UI should reuse `AppPalette`, `PaperSurface`, `SoftButton` and `TagChip`.
- No feature should require a network connection.
- Destructive actions need an undo or a snapshot.
- Add a test for behavior changes, especially around saving, migration and export.

## Regenerating fonts

Original fonts are not committed. Put them in `tools/font-src/`, then:

```powershell
uv run --with fonttools --with brotli python tools/subset_fonts.py
```

Rare glyphs intentionally fall back to the system CJK font.