Renders one Material Icons glyph by ligature name — the web equivalent of Flutter's `Icon(Icons.history)`.

```jsx
<Icon name="history" size={24} color="var(--md-on-surface-variant)" />
```

The base `Material Icons` font ships the **filled** set only: Dart constants ending in `_outlined` / `_rounded` / `_sharp` have no ligature and render as literal text. Map them to the filled name (`Icons.circle_outlined` → `panorama_fish_eye`, `Icons.insert_drive_file_outlined` → `insert_drive_file`). Otherwise use the exact ligature names the Dart source uses (`data_object`, `call_split`, `branding_watermark`, `compress`). Never substitute an emoji or a hand-drawn SVG. Icons inherit `currentColor` by default, so they tint correctly inside buttons and list tiles.
