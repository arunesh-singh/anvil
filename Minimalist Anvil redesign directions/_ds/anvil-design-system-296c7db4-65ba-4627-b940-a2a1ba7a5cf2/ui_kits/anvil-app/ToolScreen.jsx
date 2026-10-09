const { TopAppBar, TextField, Button, LinearProgress } = window.AnvilDesignSystem_296c7d;

function ToolScreen({ tool, onBack, onDone, preselected }) {
  const [file, setFile] = React.useState(preselected || null);
  const [phase, setPhase] = React.useState('idle');
  const [progress, setProgress] = React.useState(null);
  const [message, setMessage] = React.useState('Working…');
  const timers = React.useRef([]);

  React.useEffect(() => () => timers.current.forEach(clearTimeout), []);

  const pick = () => setFile('quarterly_report.' + (tool.accepts[0] || 'pdf'));

  const run = () => {
    setPhase('running');
    setProgress(null);
    setMessage('Reading file…');
    const steps = [
      [500, 0.3, 'Processing…'],
      [1200, 0.85, 'Saving…'],
    ];
    steps.forEach(([ms, p, m]) => timers.current.push(setTimeout(() => { setProgress(p); setMessage(m); }, ms)));
    timers.current.push(setTimeout(() => onDone(tool, file), 1900));
  };

  const needsFile = tool.requiresInput !== false;
  const canRun = !needsFile || !!file;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: 'var(--md-surface)' }}>
      <TopAppBar title={tool.label} onBack={onBack} />
      {phase === 'running' ? (
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 'var(--screen-padding)' }}>
          <div style={{ width: '100%' }}><LinearProgress value={progress} /></div>
          <div style={{ marginTop: 'var(--space-4)', font: 'var(--body-large)', letterSpacing: 'var(--body-large-tracking)', textAlign: 'center' }}>{message}</div>
          <div style={{ marginTop: 'var(--space-6)' }}><Button variant="outlined" onClick={() => setPhase('idle')}>Cancel</Button></div>
        </div>
      ) : (
        <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', padding: 'var(--screen-padding)' }}>
          <div style={{ font: 'var(--body-large)', letterSpacing: 'var(--body-large-tracking)' }}>{tool.desc}</div>
          <div style={{ height: 'var(--space-6)' }} />
          {needsFile ? (
            <Button variant="outlined" icon="attach_file" onClick={pick}>{tool.multi ? 'Pick files' : 'Pick file'}</Button>
          ) : null}
          {file ? (
            <div style={{ marginTop: 'var(--space-3)', font: 'var(--body-medium)', letterSpacing: 'var(--body-medium-tracking)' }}>{'Selected: ' + file}</div>
          ) : null}
          {tool.params.map((p) => (
            <div key={p.key} style={{ marginTop: 'var(--space-4)' }}>
              <TextField label={p.label} defaultValue={p.value} />
            </div>
          ))}
          <div style={{ flex: 1, minHeight: 'var(--space-6)' }} />
          <Button variant="filled" fullWidth disabled={!canRun} onClick={run}>Run</Button>
        </div>
      )}
    </div>
  );
}

Object.assign(window, { ToolScreen });
