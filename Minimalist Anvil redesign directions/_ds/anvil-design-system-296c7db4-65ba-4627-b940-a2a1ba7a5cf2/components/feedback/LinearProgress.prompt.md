Shows tool-run progress; pair it with the status message beneath, exactly like `ProgressView`.

```jsx
<LinearProgress value={0.3} />
<LinearProgress />           {/* indeterminate: "Reading PDF…" */}
```

Track is surface-container-highest, indicator is primary. Never colour it green on success — the screen navigates away instead.
