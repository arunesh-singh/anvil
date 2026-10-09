The only container treatment in Anvil — a tinted surface with a 12px radius and a level-1 shadow. No borders, no coloured left rails.

```jsx
<Card interactive onClick={open}><div style={{ padding: 'var(--tile-padding)' }}>…</div></Card>
```

Set `level` to lift a card; the background token moves with it (`--surface-level-N`), so elevation reads as tint plus shadow, not shadow alone.
