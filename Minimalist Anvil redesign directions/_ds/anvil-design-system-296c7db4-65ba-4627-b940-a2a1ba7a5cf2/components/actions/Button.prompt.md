The tap-target for any committed action; `filled` for the one primary action on a screen, `outlined` for its escape hatch, `text` inside banners and dialogs.

```jsx
<Button variant="filled" fullWidth onClick={run}>Run</Button>
<Button variant="outlined" icon="attach_file">Pick file</Button>
<Button variant="text">Dismiss</Button>
```

Variants: `filled` | `tonal` | `outlined` | `text` | `elevated`. Height is fixed at 40px with a fully-rounded corner; the label is label-large (14/20, 500). Disabled uses the 38% content / 12% container opacities, never a grey hex.
