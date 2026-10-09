A full-width selectable row with the radio on the leading edge — the only selection control in the app (Settings → Theme).

```jsx
<RadioTile label="System" value="system" selected={mode === 'system'} onSelect={setMode} />
```

Tapping anywhere on the row selects it; the whole row carries the state layer, not just the radio.
