The atom of Anvil's home screen: two per row, 8px gutters, 2.4:1 aspect, icon left of a single-line label.

```jsx
<ToolTile icon="data_object" label="CSV to JSON" onClick={open} />
```

Labels come straight from the tool registry and are Title Case with formats upper-cased ("PDF to CSV", "MP4 to GIF"). Never truncate mid-word — the label ellipsises.
