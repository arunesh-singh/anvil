const { TopAppBar, ListTile, IconButton, Button, Snackbar } = window.AnvilDesignSystem_296c7d;

function ResultScreen({ files, text, onHome, onBack }) {
  const [toast, setToast] = React.useState(null);
  React.useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2400);
    return () => clearTimeout(t);
  }, [toast]);

  return (
    <div style={{ position: 'relative', display: 'flex', flexDirection: 'column', height: '100%', background: 'var(--md-surface)' }}>
      <TopAppBar title="Result" onBack={onBack} />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: 'var(--screen-padding)', overflowY: 'auto' }}>
        <div style={{ font: 'var(--title-medium)', letterSpacing: 'var(--title-medium-tracking)' }}>Output files</div>
        <div style={{ height: 'var(--space-2)' }} />
        {files.map((name) => (
          <ListTile
            key={name}
            style={{ padding: 0 }}
            leadingIcon="insert_drive_file"
            title={name}
            trailing={<>
              <IconButton icon="open_in_new" label="Open" onClick={() => setToast('Opened ' + name)} />
              <IconButton icon="save_alt" label="Save to Files" onClick={() => setToast('Saved ' + name)} />
            </>}
          />
        ))}
        {text ? (
          <pre style={{ marginTop: 'var(--space-4)', font: 'var(--body-medium)', fontFamily: 'var(--font-mono)', color: 'var(--md-on-surface)', whiteSpace: 'pre-wrap' }}>{text}</pre>
        ) : <div style={{ flex: 1 }} />}
        <div style={{ display: 'flex', gap: 'var(--space-3)', marginTop: 'var(--space-4)' }}>
          <Button variant="filled" icon="share" fullWidth onClick={() => setToast('Shared ' + files.length + ' file' + (files.length > 1 ? 's' : ''))}>Share</Button>
          <Button variant="outlined" fullWidth onClick={onHome}>Done</Button>
        </div>
      </div>
      {toast ? <div style={{ position: 'absolute', left: 'var(--space-2)', right: 'var(--space-2)', bottom: 'var(--space-2)' }}><Snackbar>{toast}</Snackbar></div> : null}
    </div>
  );
}

Object.assign(window, { ResultScreen });
