The only chrome in Anvil — there is no bottom nav, drawer or tab bar. Root screens show the title plus actions; pushed screens show a back arrow.

```jsx
<TopAppBar title="Anvil" actions={<><IconButton icon="history" label="History" /><IconButton icon="settings" label="Settings" /></>} />
<TopAppBar title="Merge PDFs" onBack={pop} />
```

64px tall, sits flat on the surface colour with no shadow until content scrolls under it.
