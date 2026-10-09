Icon-only action for app bars and list-tile trailing slots; always give it a `label` (it becomes the tooltip, mirroring Flutter's required `tooltip:`).

```jsx
<IconButton icon="history" label="History" onClick={openHistory} />
<IconButton icon="save_alt" label="Save to Files" />
```

48×48 target with a circular state layer; `selected` swaps to the secondary-container pill. Icon colour is on-surface-variant, not primary.
